///|
test "union syntax values survive wire and JSON round trips" {
  let message = @lib.Message::new(0, 1, [
    @lib.Group::printer([
      @lib.Attribute::{
        name: "media-supported",
        values: [@lib.Keyword("iso_a4_210x297mm"), @lib.Name("Custom paper")],
      },
      @lib.Attribute::new(
        "media-col-database",
        @lib.Collection([
          @lib.Attribute::{
            name: "x-dimension",
            values: [@lib.Integer(21000), @lib.Range(10000, 30000)],
          },
        ]),
      ),
    ]),
  ])
  assert_eq(@lib.decode(@lib.encode(message)), message)
  assert_eq(@lib.message_from_json(message.to_json()), message)
  assert_eq(@lib.Capabilities::from_response(message).media().length(), 2)
}

///|
test "empty final Send-Document closes a job without inventing a document" {
  let context = @lib.RequestContext::new("ipp://localhost/ipp/print")
  let request = context.send_document(1, 27, "application/pdf", b"", last=true)
  @lib.validate_request(request)
  assert_eq(@lib.decode(@lib.encode(request)), request)
  try context.send_document(2, 27, "application/pdf", b"", last=false) catch {
    error => assert_true(error is @lib.Invalid(_))
  } noraise {
    _ => fail("empty non-final document accepted")
  }
}

///|
test "negative signed wire lengths are rejected before consuming their payload" {
  for field in ["0001788000", "80000000"] {
    let wire = @lib.bytes_from_hex("0200000b000000010438" + field + "03")
    try @lib.decode(wire) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("negative signed length accepted")
    }
  }
}

///|
test "opaque extension values respect signed wire length maxima" {
  let maximum = packet(@lib.Unknown(0x38, b"x".repeat(32767)))
  assert_eq(@lib.decode(@lib.encode(maximum)), maximum)
  for length in [32768, 65535] {
    try @lib.encode(packet(@lib.Unknown(0x38, b"x".repeat(length)))) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("unrepresentable signed value length accepted")
    }
  }
}

///|
test "octetString MAX accepts 1023 and rejects 1024 bytes in wire and JSON" {
  let maximum = packet(@lib.Octets(b"x".repeat(1023)))
  assert_eq(@lib.decode(@lib.encode(maximum)), maximum)
  let oversized = packet(@lib.Octets(b"x".repeat(1024)))
  try @lib.encode(oversized) catch {
    _ => ()
  } noraise {
    _ => fail("oversized octetString encoded")
  }
  try @lib.message_from_json(oversized.to_json()) catch {
    _ => ()
  } noraise {
    _ => fail("oversized octetString imported")
  }
}

///|
test "attribute names and keywords require a lowercase letter first" {
  for name in ["1-name", "-name", "_name", ".name", "UPPER"] {
    assert_false(@lib.valid_attribute_name(name))
  }
  for value in ["Upper", "a b", "1-name", "-name", "a/b"] {
    try @lib.encode(packet(@lib.Keyword(value))) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("invalid keyword accepted")
    }
  }
  assert_eq(
    @lib.decode(@lib.encode(packet(@lib.Keyword("a-1_b.c")))),
    packet(@lib.Keyword("a-1_b.c")),
  )
}

///|
test "unpaired UTF-16 surrogates produce typed errors on every backend" {
  for
    text in [
      String::from_array([(0xD800).unsafe_to_char()]),
      String::from_array([(0xDC00).unsafe_to_char()]),
      String::from_array(['A', (0xD800).unsafe_to_char(), 'B']),
    ] {
    try @lib.encode(packet(@lib.Name(text))) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("malformed Unicode silently changed")
    }
    try @lib.JobOptions::new(text, "application/pdf").validate() catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("invalid Unicode job name accepted")
    }
    try @lib.RequestContext::new("ipp://localhost/print", user=text) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("invalid Unicode user name accepted")
    }
  }
  let valid = packet(@lib.Name("A😀中"))
  assert_eq(@lib.decode(@lib.encode(valid)), valid)
}

///|
test "out-of-band values cannot be combined with ordinary or repeated values" {
  for
    values in [
      [@lib.OutOfBand(0x13), @lib.Name("name")],
      [@lib.OutOfBand(0x13), @lib.OutOfBand(0x13)],
    ] {
    let message = @lib.Message::new(0, 1, [
      @lib.Group::printer([@lib.Attribute::{ name: "printer-name", values, }]),
    ])
    try @lib.encode(message) catch {
      _ => ()
    } noraise {
      _ => fail("ambiguous out-of-band set accepted")
    }
  }
}

///|
test "collection depth maxima agree across binary and JSON readers" {
  for depth in [0, 1, 16, 64] {
    let mut value = @lib.Integer(2147483647)
    for _ in 0..<depth {
      value = @lib.Collection([@lib.Attribute::new("inner", value)])
    }
    let message = packet(value)
    let limits = @lib.DecodeLimits::{
      ..@lib.DecodeLimits::defaults(),
      max_collection_depth: depth,
    }
    let wire = @lib.encode(message, limits~)
    assert_eq(@lib.decode(wire, limits~), message)
    assert_eq(@lib.message_from_json(message.to_json(), limits~), message)
    if depth > 0 {
      let smaller = @lib.DecodeLimits::{
        ..limits,
        max_collection_depth: depth - 1,
      }
      try @lib.decode(wire, limits=smaller) catch {
        error => assert_true(error is @lib.Limit(_))
      } noraise {
        _ => fail("binary depth bound ignored")
      }
      try @lib.message_from_json(message.to_json(), limits=smaller) catch {
        error => assert_true(error is @lib.Limit(_))
      } noraise {
        _ => fail("JSON depth bound ignored")
      }
    }
  }
}

///|
test "JSON accounts for total wire bytes including collection delimiters" {
  let message = packet(
    @lib.Collection([
      @lib.Attribute::new("octets", @lib.Octets(b"x".repeat(1023))),
      @lib.Attribute::new("text", @lib.Text("中😀")),
    ]),
  ).with_document(b"\x00\x03\xff")
  let wire = @lib.encode(message)
  let exact = @lib.DecodeLimits::{
    ..@lib.DecodeLimits::defaults(),
    max_message_bytes: wire.length() - 3,
    max_document_bytes: 3,
  }
  assert_eq(@lib.message_from_json(message.to_json(), limits=exact), message)
  for
    limits in [
      @lib.DecodeLimits::{
        ..exact,
        max_message_bytes: exact.max_message_bytes - 1,
      },
      @lib.DecodeLimits::{ ..exact, max_document_bytes: 2, },
    ] {
    try @lib.message_from_json(message.to_json(), limits~) catch {
      error => assert_true(error is @lib.Limit(_))
    } noraise {
      _ => fail("aggregate JSON wire budget ignored")
    }
  }
}

///|
test "large reordered capability sets retain duplicate multiplicity" {
  let values : Array[@lib.IppValue] = []
  for index in 0..<16384 {
    values.push(@lib.Integer(index))
  }
  let before = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::{ name: "vendor-values", values, },
    ]),
  }
  let reversed : Array[@lib.IppValue] = []
  for index in 0..<values.length() {
    reversed.push(values[values.length() - index - 1])
  }
  let after = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::{ name: "vendor-values", values: reversed, },
    ]),
  }
  assert_eq(@lib.compare_capabilities(before, after).length(), 0)
  reversed[0] = reversed[1]
  assert_eq(@lib.compare_capabilities(before, after).length(), 1)
}

///|
test "generated valid messages preserve typed values and exact byte limits" {
  let mut seed = 0x128ef493U
  for iteration in 0..<2000 {
    seed = seed * 1664525U + 1013904223U
    let number = seed.reinterpret_as_int()
    let value = match iteration % 10 {
      0 => @lib.Integer(number)
      1 => @lib.Enumeration((number & 0x7ffffffe) + 1)
      2 => @lib.Boolean(number < 0)
      3 => @lib.Name("Report 😀 中")
      4 => @lib.TextWithLanguage("zh-cn", "打印结果")
      5 => @lib.Range(-2147483648, 2147483647)
      6 => @lib.Unknown(0x50, b"\x00\x03\xff")
      7 => @lib.Collection([@lib.Attribute::new("copies", @lib.Integer(2))])
      8 => @lib.ResolutionValue(@lib.Resolution::dpi(300, 600))
      _ => @lib.Octets(b"\x00\xff")
    }
    let document = Bytes::from_array([seed.to_byte(), (seed >> 8).to_byte(), 3])
    let message = packet(value).with_document(document)
    let wire = @lib.encode(message)
    let limits = @lib.DecodeLimits::{
      ..@lib.DecodeLimits::defaults(),
      max_message_bytes: wire.length() - document.length(),
      max_document_bytes: document.length(),
    }
    assert_eq(@lib.decode(wire, limits~), message)
    assert_eq(@lib.message_from_json(message.to_json(), limits~), message)
    assert_eq(
      @lib.encode(@lib.message_from_json(message.to_json(), limits~), limits~),
      wire,
    )
    let below = @lib.DecodeLimits::{
      ..limits,
      max_message_bytes: limits.max_message_bytes - 1,
    }
    try @lib.decode(wire, limits=below) catch {
      error => assert_true(error is @lib.Limit(_))
    } noraise {
      _ => fail("generated message exceeded its byte bound")
    }
  }
}

///|
test "semantic validators reject invalid constructed scalar and collection values" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").printer_attributes(
    1,
  )
  for
    value in [
      @lib.Keyword("Invalid keyword"),
      @lib.Collection([@lib.Attribute::new("invalid-enum", @lib.Enumeration(0))]),
    ] {
    let attributes = request.groups[0].attributes.copy()
    attributes.push(@lib.Attribute::new("vendor-option", value))
    let malformed = @lib.Message::{
      ..request,
      groups: [@lib.Group::operation(attributes)],
    }
    try @lib.validate_request(malformed) catch {
      _ => ()
    } noraise {
      _ => fail("validation claimed an unencodable scalar was valid")
    }
  }
}
