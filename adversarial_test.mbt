///|
fn packet(value : @lib.IppValue) -> @lib.Message {
  @lib.Message::new(11, 1, [
    @lib.Group::printer([@lib.Attribute::new("test-value", value)]),
  ])
}

///|
fn rejects(bytes : Bytes) -> Unit raise {
  try @lib.decode(bytes) catch {
    _ => ()
  } noraise {
    _ => fail("malformed bytes accepted")
  }
}

///|
test "all standard scalar representations survive the wire" {
  let date = @lib.IppDateTime::{
    year: 2024,
    month: 2,
    day: 29,
    hour: 12,
    minute: 30,
    second: 59,
    decisecond: 9,
    utc_direction: 43,
    utc_hours: 8,
    utc_minutes: 0,
  }
  let values : Array[@lib.IppValue] = [
    @lib.Integer(-2147483648),
    @lib.Enumeration(2147483647),
    @lib.Boolean(false),
    @lib.Range(-20, 50),
    @lib.ResolutionValue(@lib.Resolution::dpi(600, 300)),
    @lib.DateTime(date),
    @lib.Text("打印状态"),
    @lib.Name("马昀昀"),
    @lib.Keyword("iso_a4_210x297mm"),
    @lib.Uri("ipp://localhost/ipp/print"),
    @lib.UriScheme("ipps"),
    @lib.Charset("utf-8"),
    @lib.Language("zh-cn"),
    @lib.MimeType("application/pdf"),
    @lib.Octets(b"\x00\xff"),
    @lib.TextWithLanguage("zh-cn", "双面打印"),
    @lib.NameWithLanguage("en", "Report"),
    @lib.OutOfBand(0x13),
    @lib.Unknown(0x50, b"\xff\x00"),
  ]
  for value in values {
    assert_eq(@lib.decode(@lib.encode(packet(value))), packet(value))
  }
}

///|
test "malformed scalar widths and boolean values are rejected" {
  for
    hex in [
      "0200000b000000010421000178000301020303", "0200000b00000001042200017800010203",
      "0200000b00000001042300017800040000000003", "0200000b00000001043100017800010103",
      "0200000b0000000104330001780008000000040000000103", "0200000b00000001041300017800010103",
      "0200000b0000000104410001780001ff03", "0200000b00000001043500017800040003656e03",
    ] {
    rejects(@lib.bytes_from_hex(hex))
  }
}

///|
test "additional values need a preceding name and consistent tags" {
  rejects(@lib.bytes_from_hex("0200000b000000010421000000040000000103"))
  rejects(
    @lib.bytes_from_hex("0200000b00000001042100017800040000000122000000010103"),
  )
}

///|
test "group delimiters and duplicate names are checked" {
  rejects(@lib.bytes_from_hex("0200000b000000010b03"))
  rejects(@lib.bytes_from_hex("0200000b000000012100017800040000000103"))
  rejects(
    @lib.bytes_from_hex(
      "0200000b0000000104210001780004000000012100017800040000000203",
    ),
  )
}

///|
test "message and document byte limits are independent" {
  let message = packet(@lib.Text("abc")).with_document(b"\x03\x00\xff")
  let bytes = @lib.encode(message)
  let limits = @lib.DecodeLimits::{
    ..@lib.DecodeLimits::defaults(),
    max_document_bytes: 2,
  }
  try @lib.decode(bytes, limits~) catch {
    _ => ()
  } noraise {
    _ => fail("document bound ignored")
  }
  let header_length = bytes.length() - 3
  let limits = @lib.DecodeLimits::{
    ..@lib.DecodeLimits::defaults(),
    max_message_bytes: header_length,
  }
  assert_eq(@lib.decode(bytes, limits~), message)
  let limits = @lib.DecodeLimits::{
    ..limits,
    max_message_bytes: header_length - 1,
  }
  try @lib.decode(bytes, limits~) catch {
    _ => ()
  } noraise {
    _ => fail("header bound ignored")
  }
}

///|
test "collection depth and total attribute budgets are enforced" {
  let nested = @lib.Collection([
    @lib.Attribute::new(
      "inner",
      @lib.Collection([@lib.Attribute::new("n", @lib.Integer(1))]),
    ),
  ])
  let bytes = @lib.encode(packet(nested))
  for
    limits in [
      @lib.DecodeLimits::{
        ..@lib.DecodeLimits::defaults(),
        max_collection_depth: 1,
      },
      @lib.DecodeLimits::{ ..@lib.DecodeLimits::defaults(), max_attributes: 2, },
      @lib.DecodeLimits::{ ..@lib.DecodeLimits::defaults(), max_values: 2, },
    ] {
    try @lib.decode(bytes, limits~) catch {
      _ => ()
    } noraise {
      _ => fail("collection budget ignored")
    }
  }
}

///|
test "collection end marker and member framing are mandatory" {
  rejects(@lib.bytes_from_hex("0200000b000000010434000178000003"))
  rejects(
    @lib.bytes_from_hex(
      "0200000b0000000104340001780000210000000400000001370000000003",
    ),
  )
  rejects(
    @lib.bytes_from_hex(
      "0200000b00000001043400017800004a000000016d370000000003",
    ),
  )
}

///|
test "wire names and mixed value sets are validated on encode" {
  for
    attribute in [
      @lib.Attribute::{ name: "UPPER", values: [@lib.Integer(1)], },
      @lib.Attribute::{ name: "empty", values: [], },
      @lib.Attribute::{
        name: "mixed",
        values: [@lib.Integer(1), @lib.Boolean(true)],
      },
    ] {
    try
      @lib.encode(@lib.Message::new(11, 1, [@lib.Group::printer([attribute])]))
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid attribute encoded")
    }
  }
}

///|
test "IPP date validation uses leap year and UTC bounds" {
  let date = @lib.IppDateTime::{
    year: 2000,
    month: 2,
    day: 29,
    hour: 0,
    minute: 0,
    second: 0,
    decisecond: 0,
    utc_direction: 45,
    utc_hours: 0,
    utc_minutes: 0,
  }
  date.validate()
  for
    invalid in [
      @lib.IppDateTime::{ ..date, year: 1900, },
      @lib.IppDateTime::{ ..date, month: 4, day: 31, },
      @lib.IppDateTime::{ ..date, utc_direction: 0, },
      @lib.IppDateTime::{ ..date, utc_hours: 14, },
    ] {
    try invalid.validate() catch {
      _ => ()
    } noraise {
      _ => fail("invalid date accepted")
    }
  }
}

///|
test "URI parsing rejects credential injection and invalid escapes" {
  for
    uri in [
      "http://printer/ipp/print", "ipp://user:secret@printer/ipp", "ipp://host:0/x",
      "ipp://host:65536/x", "ipp://host/x?secret=1", "ipp://host/x#fragment", "ipp://host/%zz",
      "ipp://host/a\nX:1", "ipp://[::1/x",
    ] {
    try @lib.PrinterUri::parse(uri) catch {
      _ => ()
    } noraise {
      _ => fail("invalid URI accepted")
    }
  }
  assert_eq(
    @lib.PrinterUri::parse("ipps://[::1]:8631/ipp/print").http_url(),
    "https://[::1]:8631/ipp/print",
  )
}

///|
test "page ranges reject overflow overlap reversal and zero" {
  for text in ["0", "4-2", "1-3,3-5", "5,2", "2147483648", "1,,2", "1-"] {
    try @lib.parse_page_ranges(text) catch {
      _ => ()
    } noraise {
      _ => fail("invalid page range accepted")
    }
  }
  assert_eq(@lib.parse_page_ranges("1-3,5").length(), 2)
}

///|
test "chunk boundaries do not alter decoding or binary document bytes" {
  let message = packet(@lib.Text("边界")).with_document(b"\x00\x03\xff")
  let bytes = @lib.encode(message)
  for split = 0; split <= bytes.length(); split = split + 1 {
    let collector = @lib.MessageCollector::new()
    collector.feed(bytes.exact_view(end=split).to_owned())
    collector.feed(bytes.exact_view(start=split).to_owned())
    assert_eq(collector.finish(), message)
    try collector.feed(b"x") catch {
      _ => ()
    } noraise {
      _ => fail("finished collector reused")
    }
  }
}

///|
test "media collections preserve margins and reject empty printable area" {
  let spec = @lib.MediaSpec::{
    ..@lib.MediaSpec::new(@lib.MediaSize::a4()),
    margins: Some(@lib.MediaMargins::new(100, 100, 200, 200)),
    source: Some("main"),
    kind: Some("stationery"),
  }
  assert_eq(@lib.media_spec_from_collection(spec.collection()), spec)
  let invalid = @lib.MediaSpec::{
    ..spec,
    margins: Some(@lib.MediaMargins::new(0, 0, 21000, 0)),
  }
  try invalid.validate() catch {
    _ => ()
  } noraise {
    _ => fail("empty printable area accepted")
  }
}

///|
test "media request replaces keyword without modifying the original request" {
  let context = @lib.RequestContext::new("ipp://localhost/ipp/print")
  let request = context.print_job(
    1,
    @lib.JobOptions::{
      ..@lib.JobOptions::new("Report", "application/pdf"),
      media: Some("iso_a4_210x297mm"),
    },
    b"pdf",
  )
  let modified = @lib.with_media_collection(
    request,
    @lib.MediaSpec::new(@lib.MediaSize::a4()),
  )
  assert_true(modified.find(2, "media") is None)
  assert_true(modified.find(2, "media-col") is Some(_))
  assert_true(request.find(2, "media") is Some(_))
  assert_eq(modified.document, request.document)
}

///|
test "capability differences ignore set ordering and volatile counters" {
  let before = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::keywords("media-supported", ["a", "b"]),
      @lib.Attribute::new("printer-up-time", @lib.Integer(1)),
    ]),
  }
  let after = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::keywords("media-supported", ["b", "a"]),
      @lib.Attribute::new("printer-up-time", @lib.Integer(2)),
    ]),
  }
  assert_eq(@lib.compare_capabilities(before, after).length(), 0)
  assert_eq(
    @lib.compare_capabilities(before, after, include_volatile=true).length(),
    1,
  )
}

///|
test "printer readiness includes acceptance state and error reasons" {
  let capabilities = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::new("printer-state", @lib.Enumeration(3)),
      @lib.Attribute::new("printer-is-accepting-jobs", @lib.Boolean(true)),
      @lib.Attribute::keywords("printer-state-reasons", ["media-empty-error"]),
    ]),
  }
  assert_eq(capabilities.health().ready(), false)
}

///|
test "format selection never claims to convert documents" {
  let capabilities = @lib.Capabilities::{
    printer: @lib.Group::printer([
      @lib.Attribute::new(
        "document-format-supported",
        @lib.MimeType("image/jpeg"),
      ),
    ]),
  }
  assert_eq(
    capabilities.choose_format(["application/pdf", "image/jpeg"]),
    "image/jpeg",
  )
  try capabilities.choose_format(["application/pdf"]) catch {
    _ => ()
  } noraise {
    _ => fail("unadvertised format selected")
  }
}

///|
test "JSON rejects fractional request IDs and invalid tagged values" {
  let json = packet(@lib.Integer(1)).to_json()
  match json {
    Object(fields) => fields["request_id"] = Json::number(1.5)
    _ => fail("object expected")
  }
  try @lib.message_from_json(json) catch {
    _ => ()
  } noraise {
    _ => fail("fractional integer accepted")
  }
}

///|
test "unknown values cannot impersonate standard value tags" {
  try @lib.encode(packet(@lib.Unknown(0x21, b"\x00\x00\x00\x01"))) catch {
    _ => ()
  } noraise {
    _ => fail("standard tag encoded as unknown")
  }
}

///|
test "byte bounds are enforced inside collections before allocation" {
  let bytes = @lib.encode(
    packet(
      @lib.Collection([
        @lib.Attribute::new("long", @lib.Text("a long collection value")),
      ]),
    ),
  )
  let limits = @lib.DecodeLimits::{
    ..@lib.DecodeLimits::defaults(),
    max_message_bytes: 30,
  }
  try @lib.decode(bytes, limits~) catch {
    error => assert_true(error is @lib.Limit(_))
  } noraise {
    _ => fail("collection byte bound ignored")
  }
}
