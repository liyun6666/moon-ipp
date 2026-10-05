///|
test "printer URI normalization and secure HTTP mapping" {
  assert_eq(
    @lib.PrinterUri::parse("ipp://localhost/ipp/print").http_url(),
    "http://localhost:631/ipp/print",
  )
  assert_eq(
    @lib.PrinterUri::parse("ipps://[::1]:8631/ipp/print").http_url(),
    "https://[::1]:8631/ipp/print",
  )
}

///|
test "print request keeps charset and language first" {
  let context = @lib.RequestContext::new(
    "ipp://localhost:8000/ipp/print",
    user="tester",
  )
  let options = @lib.JobOptions::new("Invoice", "application/pdf")
  let request = context.print_job(41, options, b"%PDF")
  assert_eq(request.code, 2)
  assert_eq(request.groups[0].attributes[0].name, "attributes-charset")
  assert_eq(request.groups[0].attributes[1].name, "attributes-natural-language")
  assert_eq(@lib.decode(@lib.encode(request)), request)
  assert_eq(@lib.is_safe_to_retry(@lib.PrintJob), false)
  assert_eq(@lib.is_safe_to_retry(@lib.GetPrinterAttributes), true)
}

///|
test "capabilities reject unsupported document and duplex" {
  let response = @lib.Message::new(0, 1, [
    @lib.Group::printer([
      @lib.Attribute::new("printer-is-accepting-jobs", @lib.Boolean(true)),
      @lib.Attribute::new(
        "document-format-supported",
        @lib.MimeType("image/jpeg"),
      ),
      @lib.Attribute::new("copies-supported", @lib.Range(1, 99)),
      @lib.Attribute::new("sides-supported", @lib.Keyword("one-sided")),
    ]),
  ])
  let capabilities = @lib.Capabilities::from_response(response)
  let options = @lib.JobOptions::{
    ..@lib.JobOptions::new("Report", "application/pdf"),
    sides: Some(@lib.TwoSidedLongEdge),
  }
  let diagnostics = capabilities.validate_options(options)
  assert_eq(diagnostics.length(), 2)
  assert_true(@lib.diagnostics_have_errors(diagnostics))
  assert_eq(@lib.parse_page_ranges("1-3,5").length(), 2)
}
