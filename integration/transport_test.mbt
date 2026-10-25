///|
async fn exchange_with_response(
  status : Int,
  media_type : String?,
  body : Bytes,
  maximum : Int,
) -> Bytes {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let endpoint = @ipp.PrinterUri::parse(
    "ipp://127.0.0.1:\{server.addr.port()}/ipp/print",
  )
  let request = b"\x00\xffrequest"
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        let received = connection.read_request()
        assert_eq(received.meth, @http.Post)
        assert_eq(received.path, "/ipp/print")
        assert_eq(connection.read_exactly(request.length()), request)
        connection.skip_request_body()
        let headers : Map[@http.CaseInsensitiveString, String] = Map([])
        match media_type {
          Some(value) =>
            headers[@http.CaseInsensitiveString("Content-Type")] = value
          None => ()
        }
        connection.send_response(status, "Test response", extra_headers=headers)
        connection.write(body)
        connection.end_response()
      })
      let transport = @client.HttpTransport::new()
      transport.exchange(endpoint, request, maximum)
    })
  })
}

///|
async test "real HTTP preserves binary request and accepts the exact response bound" {
  let body = b"\x02\x00\x00\x00\x00\x00\x00\x01\x03"
  assert_eq(
    exchange_with_response(200, Some("Application/IPP; charset=utf-8"), body, 9),
    body,
  )
}

///|
async test "real HTTP rejects an oversized chunked body" {
  try
    exchange_with_response(200, Some("application/ipp"), b"x".repeat(16384), 9)
  catch {
    error => assert_true(error is @client.ResponseTooLarge)
  } noraise {
    _ => fail("oversized HTTP body accepted")
  }
}

///|
async test "real HTTP preserves status failures without parsing error pages" {
  for status in [401, 403, 500] {
    try
      exchange_with_response(status, Some("text/html"), b"error", 1024)
    catch {
      error =>
        match error {
          @client.HttpStatus(actual) => assert_eq(actual, status)
          _ => fail("HTTP failure lost its status")
        }
    } noraise {
      _ => fail("HTTP error accepted as IPP")
    }
  }
}

///|
async test "real HTTP rejects missing or unrelated Content-Type" {
  for
    media_type in [None, Some("text/plain"), Some("application/ipp-malicious")] {
    try exchange_with_response(200, media_type, b"body", 1024) catch {
      error => assert_true(error is @client.UnexpectedContentType(_))
    } noraise {
      _ => fail("non-IPP response accepted")
    }
  }
}
