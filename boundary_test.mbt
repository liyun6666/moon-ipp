///|
test "URI rejects malformed IPv6 literals and DNS labels" {
  for
    uri in [
      "ipp://[gg::1]/print", "ipp://[:::1]/print", "ipp://[1::2::3]/print", "ipp://[1:2:3:4:5:6:7]/print",
      "ipp://[1:2:3:4:5:6:7:8:9]/print", "ipp://[::ffff:300.1.1.1]/print", "ipp://[::ffff:01.2.3.4]/print",
      "ipp://-printer/print", "ipp://printer-/print", "ipp://a..local/print", "ipp://host/a|b",
      "ipp://host/{job}", "ipp://host/[job]",
    ] {
    try @lib.PrinterUri::parse(uri) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("malformed endpoint accepted: \{uri}")
    }
  }
  for
    uri in [
      "ipp://[::]/print", "ipp://[::1]/print", "ipps://[2001:db8::1]:443/print",
      "ipp://[1:2:3:4:5:6:7:8]/print", "ipp://[::ffff:192.0.2.1]/print", "ipp://printer.local./a%20b",
      "ipp://printer/a:b@c!$&'()*+,;=~-._",
    ] {
    let parsed = @lib.PrinterUri::parse(uri)
    assert_eq(@lib.PrinterUri::parse(parsed.text()), parsed)
  }
}

///|
test "undefined IPP 1.2 version is rejected" {
  try @lib.Version::new(1, 2) catch {
    error => assert_true(error is @lib.Invalid(_))
  } noraise {
    _ => fail("undefined protocol version accepted")
  }
}

///|
test "job state and completed counter have exact types and cardinality" {
  for
    attribute in [
      @lib.Attribute::new("job-state", @lib.Integer(9)),
      @lib.Attribute::{
        name: "job-state",
        values: [@lib.Enumeration(5), @lib.Enumeration(9)],
      },
      @lib.Attribute::new("job-impressions-completed", @lib.Integer(-1)),
      @lib.Attribute::new("job-impressions-completed", @lib.Enumeration(9)),
    ] {
    try
      @lib.Job::from_group(
        @lib.Group::job([
          @lib.Attribute::new("job-id", @lib.Integer(27)),
          attribute,
        ]),
      )
    catch {
      error => assert_true(error is @lib.Protocol(_))
    } noraise {
      _ => fail("malformed job result accepted")
    }
  }
}

///|
test "duplicate identities cannot be hidden in constructed job results" {
  let group = @lib.Group::job([
    @lib.Attribute::new("job-id", @lib.Integer(27)),
    @lib.Attribute::new("job-id", @lib.Integer(28)),
  ])
  try @lib.Job::from_group(group) catch {
    error => assert_true(error is @lib.Protocol(_))
  } noraise {
    _ => fail("duplicate job identity accepted")
  }
  let valid = @lib.Group::job([@lib.Attribute::new("job-id", @lib.Integer(27))])
  try @lib.jobs_from_response(@lib.Message::new(0, 1, [valid, valid])) catch {
    error => assert_true(error is @lib.Protocol(_))
  } noraise {
    _ => fail("same job counted twice")
  }
}

///|
test "media dimensions cannot silently choose one of several values" {
  let value = @lib.Collection([
    @lib.Attribute::new(
      "media-size",
      @lib.Collection([
        @lib.Attribute::{
          name: "x-dimension",
          values: [@lib.Integer(21000), @lib.Integer(1)],
        },
        @lib.Attribute::new("y-dimension", @lib.Integer(29700)),
      ]),
    ),
  ])
  try @lib.media_spec_from_collection(value) catch {
    error => assert_true(error is @lib.Invalid(_))
  } noraise {
    _ => fail("ambiguous paper dimension accepted")
  }
}

///|
test "request validators reject duplicate target attributes before encoding" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").printer_attributes(
    1,
  )
  request.groups[0].attributes.push(
    @lib.Attribute::new("printer-uri", @lib.Uri("ipp://other/print")),
  )
  try @lib.validate_request(request) catch {
    _ => ()
  } noraise {
    _ => fail("validator accepted conflicting targets")
  }
}

///|
test "response validation checks constructed negative status and version" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").printer_attributes(
    1,
  )
  let response = @lib.Message::new(0, 1, [
    @lib.Group::operation([
      @lib.Attribute::new("attributes-charset", @lib.Charset("utf-8")),
      @lib.Attribute::new("attributes-natural-language", @lib.Language("en")),
    ]),
  ])
  for
    invalid in [
      @lib.Message::{ ..response, code: -1, },
      @lib.Message::{
        ..response,
        version: @lib.Version::{ major: 1, minor: 2, },
      },
    ] {
    try @lib.validate_response(request, invalid) catch {
      _ => ()
    } noraise {
      _ => fail("invalid response header accepted")
    }
  }
}

///|
test "registered MIME types accept case and quoted parameters" {
  for
    format in [
      "Application/PDF", "application/vnd.hp-PCL", "text/plain; charset = UTF-8",
      "application/example; profile=\"a;b\"; version=2",
    ] {
    assert_true(@lib.valid_mime_type(format))
  }
  for
    format in [
      "text/plain;", "text/plain; charset", "text/plain; charset=", "text/plain; p=\"unterminated",
      "text/plain; charset=utf-8; CHARSET=ascii", "text/plain\r\nX:1", "*/pdf", "text/*",
    ] {
    assert_false(@lib.valid_mime_type(format))
  }
  let capabilities = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::new(
        "document-format-supported",
        @lib.MimeType("application/pdf"),
      ),
    ]),
  }
  assert_false(
    @lib.diagnostics_have_errors(
      capabilities.validate_options(
        @lib.JobOptions::new("Report", "Application/PDF"),
      ),
    ),
  )
}

///|
test "standard string bounds use UTF-8 bytes and preserve valid maxima" {
  for (tag, size_hex, length) in [("41", "0400", 1024), ("42", "0100", 256)] {
    let bytes = @lib.bytes_from_hex(
      "0200000b0000000104" +
      tag +
      "000178" +
      size_hex +
      "78".repeat(length) +
      "03",
    )
    try @lib.decode(bytes) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("wire string byte limit ignored")
    }
  }
  for
    value in [
      @lib.Name("x".repeat(256)),
      @lib.Text("x".repeat(1024)),
      @lib.Name("中".repeat(86)),
      @lib.Keyword("中文"),
      @lib.Language("x".repeat(64)),
      @lib.Charset("x".repeat(64)),
      @lib.NameWithLanguage("en", "x".repeat(256)),
    ] {
    try @lib.encode(packet(value)) catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("invalid standard string accepted")
    }
  }
  for
    value in [
      @lib.Name("x".repeat(255)),
      @lib.Text("x".repeat(1023)),
      @lib.Name("中".repeat(85)),
    ] {
    assert_eq(@lib.decode(@lib.encode(packet(value))), packet(value))
  }
}

///|
test "empty groups and oversized JSON octets cannot bypass resource budgets" {
  let limits = @lib.DecodeLimits::{
    ..@lib.DecodeLimits::defaults(),
    max_attributes: 1,
  }
  let bytes = @lib.bytes_from_hex("0200000b0000000101010103")
  try @lib.decode(bytes, limits~) catch {
    error => assert_true(error is @lib.Limit(_))
  } noraise {
    _ => fail("empty group budget ignored")
  }
  let message = @lib.Message::new(11, 1, [
    @lib.Group::operation([]),
    @lib.Group::job([]),
    @lib.Group::printer([]),
  ])
  try @lib.encode(message, limits~) catch {
    error => assert_true(error is @lib.Limit(_))
  } noraise {
    _ => fail("group count limit ignored on encode")
  }
  let json = packet(@lib.Octets(b"x".repeat(65536))).to_json()
  try @lib.message_from_json(json) catch {
    error => assert_true(error is @lib.Limit(_))
  } noraise {
    _ => fail("oversized octets allocated from JSON")
  }
}

///|
test "MIME parameter names and charset are case insensitive while other values are not" {
  let caps = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::new(
        "document-format-supported",
        @lib.MimeType("text/plain; charset=utf-8; profile=\"A;B\""),
      ),
    ]),
  }
  let valid = @lib.JobOptions::new(
    "Report", "TEXT/PLAIN; PROFILE=\"A;B\"; CHARSET=\"UTF-8\"",
  )
  assert_false(@lib.diagnostics_have_errors(caps.validate_options(valid)))
  let changed = @lib.JobOptions::{
    ..valid,
    document_format: "text/plain; charset=utf-8; profile=\"a;b\"",
  }
  assert_true(@lib.diagnostics_have_errors(caps.validate_options(changed)))
}

///|
test "ambiguous printer groups are rejected instead of selecting the first" {
  let group = @lib.Group::printer([
    @lib.Attribute::new("printer-name", @lib.Name("Printer")),
  ])
  try
    @lib.Capabilities::from_response(@lib.Message::new(0, 1, [group, group]))
  catch {
    error => assert_true(error is @lib.Protocol(_))
  } noraise {
    _ => fail("ambiguous capabilities accepted")
  }
}

///|
test "media size names retain custom human-readable values" {
  let spec = @lib.MediaSpec::{
    ..@lib.MediaSpec::new(@lib.MediaSize::a4()),
    name: Some("办公室 A4"),
  }
  assert_eq(@lib.media_spec_from_collection(spec.collection()), spec)
}

///|
test "extended value tag is rejected rather than parsed as a normal tag" {
  try
    @lib.decode(@lib.bytes_from_hex("0200000b00000001047f000178000003"))
  catch {
    error => assert_true(error is @lib.Unsupported(_))
  } noraise {
    _ => fail("unsupported extended value tag accepted")
  }
  try @lib.encode(packet(@lib.Unknown(0x7f, b""))) catch {
    error => assert_true(error is @lib.Unsupported(_))
  } noraise {
    _ => fail("extended value tag encoded with the short layout")
  }
}

///|
test "deterministic malformed wire corpus never panics and valid results re-encode" {
  let original = @lib.encode(
    @lib.RequestContext::new("ipp://localhost/ipp/print").printer_attributes(1),
  ).to_array()
  let mut seed = 0x42bd97e1U
  for iteration in 0..<5000 {
    seed = seed * 1664525U + 1013904223U
    let length = if iteration % 2 == 0 {
      original.length()
    } else {
      (seed % 128U).reinterpret_as_int()
    }
    let bytes = if iteration % 2 == 0 {
      original.copy()
    } else {
      Array::make(length, b'\x00')
    }
    for _ in 0..<4 {
      seed = seed * 1664525U + 1013904223U
      if length > 0 {
        let index = (seed % length.reinterpret_as_uint()).reinterpret_as_int()
        bytes[index] = (seed >> 24).to_byte()
      }
    }
    try @lib.decode(Bytes::from_array(bytes)) catch {
      _ => ()
    } noraise {
      message => assert_eq(@lib.decode(@lib.encode(message)), message)
    }
  }
}
