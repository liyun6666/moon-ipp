///|
priv struct StubTransport {
  requests : Array[@ipp.Message]
  wrong_id : Bool
  slow : Bool
  fail_print : Bool
  reject_print : Bool
  wrong_job_id : Bool
  omit_job_id : Bool
}

///|
impl Transport for StubTransport with fn exchange(
  self,
  _endpoint,
  bytes,
  _maximum,
) {
  let request = @ipp.decode(bytes)
  self.requests.push(request)
  if self.slow {
    @async.sleep(30)
  }
  if self.fail_print && request.code == 2 {
    raise @ipp.Protocol("lost response")
  }
  let groups = [
    @ipp.Group::operation([
      @ipp.Attribute::new("attributes-charset", @ipp.Charset("utf-8")),
      @ipp.Attribute::new("attributes-natural-language", @ipp.Language("en")),
    ]),
  ]
  if request.code == 11 {
    groups.push(
      @ipp.Group::printer([
        @ipp.Attribute::new(
          "printer-name",
          @ipp.Name("Independent test transport"),
        ),
        @ipp.Attribute::new(
          "document-format-supported",
          @ipp.MimeType("application/pdf"),
        ),
        @ipp.Attribute::new("copies-supported", @ipp.Range(1, 10)),
      ]),
    )
  }
  if request.code == 2 || request.code == 9 || request.code == 5 {
    let attributes = [@ipp.Attribute::new("job-state", @ipp.Enumeration(9))]
    if !self.omit_job_id {
      attributes.push(
        @ipp.Attribute::new(
          "job-id",
          @ipp.Integer(if self.wrong_job_id { 28 } else { 27 }),
        ),
      )
    }
    groups.push(@ipp.Group::job(attributes))
  }
  let id = request.request_id + (if self.wrong_id { 1 } else { 0 })
  let status = if self.reject_print && request.code == 2 { 0x040b } else { 0 }
  @ipp.encode(@ipp.Message::new(status, id, groups))
}

///|
fn stub() -> StubTransport {
  {
    requests: [],
    wrong_id: false,
    slow: false,
    fail_print: false,
    reject_print: false,
    wrong_job_id: false,
    omit_job_id: false,
  }
}

///|
async test "client preflight validates before submitting" {
  let transport = stub()
  let client = Client::new("ipp://localhost/ipp/print", transport)
  let job = client.print_job(
    @ipp.JobOptions::new("Report", "application/pdf"),
    b"%PDF",
  )
  assert_eq(job.id, 27)
  assert_eq(transport.requests.map(fn(request) { request.code }), [11, 4, 2])
}

///|
async test "unsupported preflight never submits document" {
  let transport = stub()
  let client = Client::new("ipp://localhost/ipp/print", transport)
  try
    client.print_job(@ipp.JobOptions::new("Photo", "image/jpeg"), b"jpeg")
  catch {
    _ => ()
  } noraise {
    _ => fail("expected unsupported format")
  }
  assert_eq(transport.requests.length(), 1)
}

///|
async test "lost print response is uncertain and never retried" {
  let transport = StubTransport::{ ..stub(), fail_print: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  try
    client.print_job(
      @ipp.JobOptions::new("Report", "application/pdf"),
      b"%PDF",
      preflight=false,
    )
  catch {
    error => assert_true(error is SubmissionUncertain(_))
  } noraise {
    _ => fail("expected uncertain submission")
  }
  assert_eq(transport.requests.length(), 1)
}

///|
async test "timeouts cancel exchange and release request lock" {
  let transport = StubTransport::{ ..stub(), slow: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport, timeout_ms=1)
  try client.printer_attributes() catch {
    _ => ()
  } noraise {
    _ => fail("expected timeout")
  }
  assert_eq(client.busy, false)
}

///|
async test "mismatched transaction rejected" {
  let transport = StubTransport::{ ..stub(), wrong_id: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  try client.printer_attributes() catch {
    _ => ()
  } noraise {
    _ => fail("expected mismatched response")
  }
}

///|
async test "wait terminates on completed job" {
  let client = Client::new("ipp://localhost/ipp/print", stub())
  let observations = client.wait_job(27)
  assert_eq(observations.length(), 1)
  assert_eq(observations[0].job.state, Some(@ipp.Completed))
}

///|
async test "known printer rejection remains distinct from unknown submission outcome" {
  let transport = StubTransport::{ ..stub(), reject_print: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  try
    client.print_job(
      @ipp.JobOptions::new("Report", "application/pdf"),
      b"pdf",
      preflight=false,
    )
  catch {
    error => assert_true(error is @ipp.Protocol(_))
  } noraise {
    _ => fail("expected server rejection")
  }
  assert_eq(transport.requests.length(), 1)
}

///|
async test "concurrent caller cannot interleave a transaction" {
  let transport = StubTransport::{ ..stub(), slow: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  @async.with_task_group(async fn(group) {
    let first = group.spawn(async fn() { client.printer_attributes() })
    @async.sleep(1)
    try client.printer_attributes() catch {
      error => assert_true(error is ConcurrentRequest)
    } noraise {
      _ => fail("concurrent request accepted")
    }
    let _ = first.wait()
  })
  assert_eq(transport.requests.length(), 1)
}

///|
async test "query rejects a different job even on the first poll" {
  let transport = StubTransport::{ ..stub(), wrong_job_id: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  try client.wait_job(27) catch {
    error => assert_true(error is @ipp.Protocol(_))
  } noraise {
    _ => fail("accepted completion of a different job")
  }
  assert_eq(transport.requests.length(), 1)
}

///|
async test "accepted print without job identity requires reconciliation" {
  let transport = StubTransport::{ ..stub(), omit_job_id: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  try
    client.print_job(
      @ipp.JobOptions::new("Report", "application/pdf"),
      b"pdf",
      preflight=false,
    )
  catch {
    error => assert_true(error is SubmissionUncertain(_))
  } noraise {
    _ => fail("accepted print has no job identity")
  }
  assert_eq(transport.requests.length(), 1)
}

///|
async test "accepted create without job identity cannot be safely repeated" {
  let transport = StubTransport::{ ..stub(), omit_job_id: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  try
    client.create_job(@ipp.JobOptions::new("Report", "application/pdf"))
  catch {
    error => assert_true(error is SubmissionUncertain(_))
  } noraise {
    _ => fail("accepted create has no job identity")
  }
  assert_eq(transport.requests.length(), 1)
}
