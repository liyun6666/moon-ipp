///|
priv struct StubTransport {
  requests : Array[@ipp.Message]
  wrong_id : Bool
  slow : Bool
  fail_print : Bool
  reject_print : Bool
  wrong_job_id : Bool
  omit_job_id : Bool
  omit_job_group : Bool
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
  if (
      request.code == 2 ||
      request.code == 9 ||
      request.code == 5 ||
      request.code == 6
    ) &&
    !self.omit_job_group {
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
    omit_job_group: false,
  }
}

///|
test "authorization rejects control bytes before any HTTP request" {
  for
    value in [
      "Bearer token\u0000", "Bearer token\u007f", "Bearer token\r\nX: 1", "   ",
    ] {
    try HttpTransport::new(authorization=value) catch {
      error => assert_true(error is @ipp.Invalid(_))
    } noraise {
      _ => fail("invalid HTTP authorization accepted")
    }
  }
}

///|
async test "client refuses a different target before any transport call" {
  let transport = stub()
  let client = Client::new("ipp://localhost/ipp/print", transport)
  let request = @ipp.RequestContext::new("ipp://other/ipp/print").print_job(
    1,
    @ipp.JobOptions::new("Report", "application/pdf"),
    b"pdf",
  )
  try client.exchange(request) catch {
    error => assert_true(error is @ipp.Invalid(_))
  } noraise {
    _ => fail("sent request to the wrong printer")
  }
  assert_eq(transport.requests.length(), 0)
}

///|
async test "invalid print arguments are rejected before preflight network IO" {
  let transport = stub()
  let client = Client::new("ipp://localhost/ipp/print", transport)
  for document in [b"", b"pdf"] {
    let options = @ipp.JobOptions::new(
      if document.is_empty() {
        "Report"
      } else {
        ""
      },
      "application/pdf",
    )
    try client.print_job(options, document) catch {
      error => assert_true(error is @ipp.Invalid(_))
    } noraise {
      _ => fail("invalid submission accepted")
    }
  }
  assert_eq(transport.requests.length(), 0)
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

///|
async test "accepted Send-Document must identify the original job" {
  for
    transport in [
      StubTransport::{ ..stub(), wrong_job_id: true, },
      StubTransport::{ ..stub(), omit_job_id: true, },
    ] {
    let client = Client::new("ipp://localhost/ipp/print", transport)
    try client.send_document(27, "application/pdf", b"pdf") catch {
      error => assert_true(error is SubmissionUncertain(_))
    } noraise {
      _ => fail("document accepted without matching job identity")
    }
    assert_eq(transport.requests.length(), 1)
    assert_false(client.busy)
  }
}

///|
async test "empty final document is sent once and preserves the job identity" {
  let transport = stub()
  let client = Client::new("ipp://localhost/ipp/print", transport)
  let response = client.send_document(27, "application/pdf", b"", last=true)
  assert_eq(@ipp.job_from_response(response).id, 27)
  assert_eq(transport.requests.length(), 1)
  assert_true(transport.requests[0].document.is_empty())
  try client.send_document(27, "application/pdf", b"", last=false) catch {
    error => assert_true(error is @ipp.Invalid(_))
  } noraise {
    _ => fail("empty non-final request sent")
  }
  assert_eq(transport.requests.length(), 1)
}

///|
async test "CUPS empty final acknowledgement may omit a repeated job group" {
  let transport = StubTransport::{ ..stub(), omit_job_group: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  let response = client.send_document(27, "application/pdf", b"", last=true)
  assert_eq(response.code, 0)
  assert_true(response.find_group(2) is None)
  assert_eq(transport.requests.length(), 1)
  assert_false(client.busy)
}

///|
async test "request ID wraps to a positive ID and a failed exchange releases the client" {
  let transport = StubTransport::{ ..stub(), fail_print: true, }
  let client = Client::new("ipp://localhost/ipp/print", transport)
  client.next_id = 2147483647
  try
    client.print_job(
      @ipp.JobOptions::new("Report", "application/pdf"),
      b"pdf",
      preflight=false,
    )
  catch {
    error => assert_true(error is SubmissionUncertain(_))
  } noraise {
    _ => fail("expected lost submission response")
  }
  let _ = client.printer_attributes()
  assert_eq(transport.requests.map(request => request.request_id), [
    2147483647, 1,
  ])
  assert_false(client.busy)
}
