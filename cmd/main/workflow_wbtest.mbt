///|
priv struct WorkflowTransport {
  requests : Array[Int32]
  terminal : Int32
  lost : Bool
}

///|
impl @client.Transport for WorkflowTransport with fn exchange(
  self,
  _endpoint,
  bytes,
  _maximum,
) {
  let request = @ipp.decode(bytes)
  self.requests.push(request.code)
  if self.lost && request.code == 2 {
    raise @ipp.Protocol("lost print acknowledgement")
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
        @ipp.Attribute::new("printer-name", @ipp.Name("Workflow fixture")),
        @ipp.Attribute::new(
          "document-format-supported",
          @ipp.MimeType("application/pdf"),
        ),
        @ipp.Attribute::new("copies-supported", @ipp.Range(1, 10)),
      ]),
    )
  }
  if request.code == 2 || request.code == 9 {
    groups.push(
      @ipp.Group::job([
        @ipp.Attribute::new("job-id", @ipp.Integer(27)),
        @ipp.Attribute::new(
          "job-state",
          @ipp.Enumeration(if request.code == 2 { 3 } else { self.terminal }),
        ),
      ]),
    )
  }
  @ipp.encode(@ipp.Message::new(0, request.request_id, groups))
}

///|
fn workflow_arguments(path : String) -> @cli.Arguments raise @ipp.IppError {
  @cli.parse([
    "print", "--uri", "ipp://localhost/ipp/print", "--input", "report.pdf", "--wait",
    "--polls", "1", "--output", path,
  ])
}

///|
fn workflow_field(json : Json, name : String) -> Json raise {
  match json {
    Object(fields) => fields.get(name).unwrap()
    _ => fail("object expected")
  }
}

///|
async test "receipt records accepted identity before successful tracking completes" {
  let directory = @fs.tmpdir(prefix="moon-ipp-workflow-")
  let path = directory + "/receipt.json"
  defer {
    @fs.remove(path)
    @fs.rmdir(directory)
  }
  let transport = WorkflowTransport::{ requests: [], terminal: 9, lost: false, }
  let result = print_document(
    @client.Client::new("ipp://localhost/ipp/print", transport),
    workflow_arguments(path),
    b"pdf",
  )
  assert_eq(workflow_field(result, "state"), Json::string("completed"))
  assert_eq(
    workflow_field(workflow_field(result, "job"), "id"),
    Json::number(27),
  )
  assert_eq(read_json(path), result)
  assert_eq(transport.requests.filter(code => code == 2).length(), 1)
  assert_false(@fs.exists(path + ".moon-ipp-tmp"))
}

///|
async test "an existing receipt refuses another print before any network IO" {
  let directory = @fs.tmpdir(prefix="moon-ipp-workflow-")
  let path = directory + "/receipt.json"
  defer {
    @fs.remove(path)
    @fs.rmdir(directory)
  }
  @fs.write_file(path, "original receipt")
  let transport = WorkflowTransport::{ requests: [], terminal: 9, lost: false, }
  try
    print_document(
      @client.Client::new("ipp://localhost/ipp/print", transport),
      workflow_arguments(path),
      b"pdf",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("receipt reused")
  }
  assert_eq(transport.requests.length(), 0)
  assert_eq(@fs.read_file(path).text(), "original receipt")
}

///|
async test "lost submission is recorded as unknown and is never automatically resent" {
  let directory = @fs.tmpdir(prefix="moon-ipp-workflow-")
  let path = directory + "/receipt.json"
  defer {
    @fs.remove(path)
    @fs.rmdir(directory)
  }
  let transport = WorkflowTransport::{ requests: [], terminal: 9, lost: true, }
  try
    print_document(
      @client.Client::new("ipp://localhost/ipp/print", transport),
      workflow_arguments(path),
      b"pdf",
    )
  catch {
    error => assert_true(error is @client.SubmissionUncertain(_))
  } noraise {
    _ => fail("lost submission treated as successful")
  }
  let result = read_json(path)
  assert_eq(workflow_field(result, "state"), Json::string("outcome-unknown"))
  assert_eq(workflow_field(result, "job"), Json::null())
  assert_eq(transport.requests.filter(code => code == 2).length(), 1)
}

///|
async test "canceled aborted and stalled jobs preserve their accepted identity and fail" {
  for terminal in [7, 8, 3] {
    let directory = @fs.tmpdir(prefix="moon-ipp-workflow-")
    let path = directory + "/receipt.json"
    defer {
      @fs.remove(path)
      @fs.rmdir(directory)
    }
    let transport = WorkflowTransport::{ requests: [], terminal, lost: false, }
    try
      print_document(
        @client.Client::new("ipp://localhost/ipp/print", transport),
        workflow_arguments(path),
        b"pdf",
      )
    catch {
      error =>
        if terminal == 3 {
          assert_true(error is @client.JobWaitExpired(27))
        } else {
          assert_true(error is @ipp.Protocol(_))
        }
    } noraise {
      _ => fail("unsuccessful terminal state treated as completed")
    }
    let result = read_json(path)
    assert_eq(
      workflow_field(workflow_field(result, "job"), "id"),
      Json::number(27),
    )
    assert_eq(
      workflow_field(result, "state"),
      Json::string(
        if terminal == 7 {
          "canceled"
        } else if terminal == 8 {
          "aborted"
        } else {
          "tracking-error"
        },
      ),
    )
    assert_eq(transport.requests.filter(code => code == 2).length(), 1)
  }
}

///|
async test "receipt replacement does not overwrite a stale temporary file" {
  let directory = @fs.tmpdir(prefix="moon-ipp-workflow-")
  let path = directory + "/receipt.json"
  let temporary = path + ".moon-ipp-tmp"
  defer {
    @fs.remove(path)
    @fs.remove(temporary)
    @fs.rmdir(directory)
  }
  @fs.write_file(path, "original")
  @fs.write_file(temporary, "stale")
  try update_receipt(path, Json::null()) catch {
    _ => ()
  } noraise {
    _ => fail("stale file overwritten")
  }
  assert_eq(@fs.read_file(path).text(), "original")
  assert_eq(@fs.read_file(temporary).text(), "stale")
}

///|
priv struct SlowWorkflowTransport {
  base : WorkflowTransport
}

///|
async test "transient Windows replacement conflicts preserve old receipt until atomic success" {
  let directory = @fs.tmpdir(prefix="moon-ipp-replace-")
  let path = directory + "/receipt.json"
  let temporary = path + ".moon-ipp-tmp"
  defer {
    if @fs.exists(temporary) {
      @fs.remove(temporary)
    }
    @fs.remove(path)
    @fs.rmdir(directory)
  }
  @fs.write_file(path, "original receipt")
  @fs.write_file(temporary, "complete replacement")
  let conflicts = [5, 32, 33]
  let mut calls = 0
  replace_receipt(
    () => {
      assert_eq(@fs.read_file(path).text(), "original receipt")
      calls += 1
      if calls <= conflicts.length() {
        raise @os_error.OSError(
          conflicts[calls - 1],
          context="injected Windows replacement conflict",
        )
      }
      @fs.rename(temporary, path, replace=true)
    },
    windows=true,
  )
  assert_true(calls >= 4 && calls <= 8)
  assert_eq(@fs.read_file(path).text(), "complete replacement")
  assert_false(@fs.exists(temporary))
}

///|
async test "persistent replacement denial remains bounded and leaves receipt intact" {
  let directory = @fs.tmpdir(prefix="moon-ipp-replace-")
  let path = directory + "/receipt.json"
  defer {
    @fs.remove(path)
    @fs.rmdir(directory)
  }
  @fs.write_file(path, "original receipt")
  let mut calls = 0
  try
    replace_receipt(
      () => {
        calls += 1
        raise @os_error.OSError(5, context="persistent replacement denial")
      },
      windows=true,
    )
  catch {
    @os_error.OSError(5, context~) =>
      assert_eq(context, "persistent replacement denial")
    _ => fail("replacement error was changed")
  } noraise {
    _ => fail("persistent denial treated as success")
  }
  assert_eq(calls, 8)
  assert_eq(@fs.read_file(path).text(), "original receipt")
}

///|
async test "replacement retries do not swallow other errors or Unix failures" {
  let mut calls = 0
  try
    replace_receipt(
      () => {
        calls += 1
        raise @os_error.OSError(2, context="missing replacement source")
      },
      windows=true,
    )
  catch {
    @os_error.OSError(2, ..) => ()
    _ => fail("missing source error was changed")
  } noraise {
    _ => fail("missing source treated as success")
  }
  assert_eq(calls, 1)
  calls = 0
  try
    replace_receipt(
      () => {
        calls += 1
        raise @os_error.OSError(5, context="non-Windows error")
      },
      windows=false,
    )
  catch {
    @os_error.OSError(5, ..) => ()
    _ => fail("Unix error was changed")
  } noraise {
    _ => fail("Unix error treated as success")
  }
  assert_eq(calls, 1)
  calls = 0
  try
    replace_receipt(
      () => {
        calls += 1
        raise @ipp.Protocol("non-filesystem interruption")
      },
      windows=true,
    )
  catch {
    @ipp.Protocol("non-filesystem interruption") => ()
    _ => fail("interruption was changed")
  } noraise {
    _ => fail("interruption treated as success")
  }
  assert_eq(calls, 1)
}

///|
impl @client.Transport for SlowWorkflowTransport with fn exchange(
  self,
  endpoint,
  bytes,
  maximum,
) {
  if @ipp.decode(bytes).code == 9 {
    @async.sleep(10000)
  }
  @client.Transport::exchange(self.base, endpoint, bytes, maximum)
}

///|
async test "canceling tracking preserves the accepted receipt and never resubmits" {
  let directory = @fs.tmpdir(prefix="moon-ipp-workflow-")
  let path = directory + "/receipt.json"
  defer {
    @fs.remove(path)
    @fs.rmdir(directory)
  }
  let transport = SlowWorkflowTransport::{
    base: WorkflowTransport::{ requests: [], terminal: 9, lost: false, },
  }
  try
    @async.with_timeout(2000, () => {
      print_document(
        @client.Client::new("ipp://localhost/ipp/print", transport),
        workflow_arguments(path),
        b"pdf",
      )
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("tracking was not interrupted")
  }
  let result = read_json(path)
  assert_eq(workflow_field(result, "state"), Json::string("tracking-error"))
  assert_eq(
    workflow_field(workflow_field(result, "job"), "id"),
    Json::number(27),
  )
  assert_eq(transport.base.requests.filter(code => code == 2).length(), 1)
}
