///|
test "multiple job groups remain distinct" {
  let response = @lib.Message::new(0, 1, [
    @lib.Group::job([
      @lib.Attribute::new("job-id", @lib.Integer(10)),
      @lib.Attribute::new("job-state", @lib.Enumeration(5)),
    ]),
    @lib.Group::job([
      @lib.Attribute::new("job-id", @lib.Integer(11)),
      @lib.Attribute::new("job-state", @lib.Enumeration(9)),
    ]),
  ])
  let jobs = @lib.jobs_from_response(@lib.decode(@lib.encode(response)))
  assert_eq(jobs.length(), 2)
  assert_eq(jobs[0].id, 10)
  assert_eq(jobs[1].state, Some(@lib.Completed))
  assert_true(@lib.Completed.terminal())
  assert_eq(@lib.OutcomeUnknown.may_submit_again(), false)
}

///|
test "all partial headers and attributes are rejected" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").printer_attributes(
    1,
  )
  let bytes = @lib.encode(request)
  for length = 0; length < bytes.length(); length = length + 1 {
    let failed = try {
      let _ = @lib.decode(bytes.exact_view(end=length).to_owned())
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}

///|
test "response correlation prevents accepting a different transaction" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").printer_attributes(
    1,
  )
  let response = @lib.Message::new(0, 2, [
    @lib.Group::operation([
      @lib.Attribute::new("attributes-charset", @lib.Charset("utf-8")),
      @lib.Attribute::new("attributes-natural-language", @lib.Language("en")),
    ]),
  ])
  let failed = try {
    @lib.validate_response(request, response)
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
