///|
test "custom named media can be selected from advertised defaults and encoded" {
  let name = "办公室专用 A4"
  let capabilities = @lib.Capabilities::from_response(
    @lib.Message::new(0, 1, [
      @lib.Group::printer([
        @lib.Attribute::new("media-default", @lib.Name(name)),
        @lib.Attribute::{
          name: "media-supported",
          values: [@lib.Keyword("iso_a4_210x297mm"), @lib.Name(name)],
        },
      ]),
    ]),
  )
  let options = capabilities.default_options("Named stock", "application/pdf")
  assert_eq(options.media, Some(name))
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").print_job(
    1, options, b"pdf",
  )
  assert_eq(request.find(2, "media").unwrap().values, [@lib.Name(name)])
  @lib.validate_request(request)
  assert_eq(@lib.decode(@lib.encode(request)), request)
  for invalid in ["", "中".repeat(86)] {
    let options = @lib.JobOptions::{ ..options, media: Some(invalid), }
    try options.validate() catch {
      error => assert_true(error is @lib.Invalid(_))
    } noraise {
      _ => fail("invalid media name accepted")
    }
  }
}

///|
test "conflicting or mistyped printer health values cannot report ready" {
  for
    invalid in [
      @lib.Attribute::{
        name: "printer-is-accepting-jobs",
        values: [@lib.Boolean(true), @lib.Boolean(false)],
      },
      @lib.Attribute::new("printer-state", @lib.Integer(3)),
      @lib.Attribute::new("queued-job-count", @lib.Integer(-1)),
    ] {
    let attributes = [
      @lib.Attribute::new("printer-state", @lib.Enumeration(3)),
      @lib.Attribute::new("printer-is-accepting-jobs", @lib.Boolean(true)),
    ].filter(attribute => attribute.name != invalid.name)
    attributes.push(invalid)
    let printer = @lib.Group::printer(attributes)
    let direct = @lib.Capabilities::{ printer, }
    assert_false(direct.health().ready())
    assert_true(@lib.diagnostics_have_errors(direct.health().diagnostics))
    try
      @lib.Capabilities::from_response(@lib.Message::new(0, 1, [printer]))
    catch {
      error => assert_true(error is @lib.Protocol(_))
    } noraise {
      _ => fail("malformed printer health was accepted")
    }
  }
}

///|
test "unknown optional job attributes remain unavailable instead of invalid" {
  let job = @lib.Job::from_group(
    @lib.Group::job([
      @lib.Attribute::new("job-id", @lib.Integer(27)),
      @lib.Attribute::new("job-state", @lib.OutOfBand(0x12)),
      @lib.Attribute::new("job-name", @lib.OutOfBand(0x13)),
      @lib.Attribute::new("job-state-reasons", @lib.OutOfBand(0x12)),
      @lib.Attribute::new("job-impressions-completed", @lib.OutOfBand(0x12)),
    ]),
  )
  assert_eq(job.id, 27)
  assert_eq(job.state, None)
  assert_eq(job.name, None)
  assert_eq(job.reasons, [])
  assert_eq(job.impressions_completed, None)
}

///|
test "unavailable advertised capabilities are unknown rather than explicit rejection" {
  let capabilities = @lib.Capabilities::from_response(
    @lib.Message::new(0, 1, [
      @lib.Group::printer([
        @lib.Attribute::new("operations-supported", @lib.OutOfBand(0x12)),
        @lib.Attribute::new("document-format-supported", @lib.OutOfBand(0x13)),
        @lib.Attribute::new("copies-supported", @lib.OutOfBand(0x12)),
        @lib.Attribute::new(
          "printer-resolution-supported",
          @lib.OutOfBand(0x12),
        ),
      ]),
    ]),
  )
  assert_eq(capabilities.supports_operation(@lib.PrintJob), None)
  let options = @lib.JobOptions::{
    ..@lib.JobOptions::new("Report", "application/pdf"),
    resolution: Some(@lib.Resolution::dpi(300, 300)),
  }
  let diagnostics = capabilities.validate_options(options)
  assert_false(@lib.diagnostics_have_errors(diagnostics))
  assert_eq(diagnostics.length(), 3)
}

///|
test "out-of-band job fields do not weaken the required job identity" {
  for id in [@lib.OutOfBand(0x12), @lib.OutOfBand(0x13), @lib.Integer(0)] {
    try
      @lib.Job::from_group(@lib.Group::job([@lib.Attribute::new("job-id", id)]))
    catch {
      error => assert_true(error is @lib.Protocol(_))
    } noraise {
      _ => fail("job without identity accepted")
    }
  }
}

///|
test "valid idle stopped and unavailable status retain distinct readiness" {
  for
    (state, accepting, expected) in [
      (@lib.Enumeration(3), @lib.Boolean(true), true),
      (@lib.Enumeration(4), @lib.Boolean(true), true),
      (@lib.Enumeration(5), @lib.Boolean(true), false),
      (@lib.Enumeration(3), @lib.Boolean(false), false),
      (@lib.OutOfBand(0x12), @lib.Boolean(true), false),
      (@lib.Enumeration(3), @lib.OutOfBand(0x13), false),
    ] {
    let capabilities = @lib.Capabilities::from_response(
      @lib.Message::new(0, 1, [
        @lib.Group::printer([
          @lib.Attribute::new("printer-state", state),
          @lib.Attribute::new("printer-is-accepting-jobs", accepting),
        ]),
      ]),
    )
    assert_eq(capabilities.health().ready(), expected)
  }
}

///|
test "mistyped capability values are rejected while future attributes remain opaque" {
  for
    attribute in [
      @lib.Attribute::new("operations-supported", @lib.Integer(2)),
      @lib.Attribute::new(
        "document-format-supported",
        @lib.Name("application/pdf"),
      ),
      @lib.Attribute::new("printer-resolution-supported", @lib.Integer(300)),
    ] {
    try
      @lib.Capabilities::from_response(
        @lib.Message::new(0, 1, [@lib.Group::printer([attribute])]),
      )
    catch {
      error => assert_true(error is @lib.Protocol(_))
    } noraise {
      _ => fail("mistyped advertised capability accepted")
    }
  }
  let capabilities = @lib.Capabilities::from_response(
    @lib.Message::new(0, 1, [
      @lib.Group::printer([
        @lib.Attribute::new("vendor-new-field", @lib.Unknown(0x50, b"\x00\xff")),
      ]),
    ]),
  )
  assert_eq(capabilities.printer.find("vendor-new-field").unwrap().values, [
    @lib.Unknown(0x50, b"\x00\xff"),
  ])
}
