///|
#external
priv type RedirectProbe

///|
extern "js" fn start_redirect_probe() -> @js_async.Promise[RedirectProbe] =
  #| async () => {
  #|   const { createServer } = await import('node:http');
  #|   const probe = { server: null, targetHits: 0, starts: 0, received: '', requests: 0 };
  #|   probe.server = createServer((req, res) => {
  #|     const chunks = [];
  #|     req.on('data', chunk => chunks.push(chunk));
  #|     req.on('end', () => {
  #|       probe.received = Buffer.concat(chunks).toString('hex');
  #|       probe.requests++;
  #|       if (req.url === '/redirect') {
  #|         probe.starts++;
  #|         res.writeHead(307, { Location: '/target' });
  #|         res.end();
  #|       } else if (req.url === '/slow') {
  #|         const timer = setTimeout(() => {
  #|           res.writeHead(200, { 'Content-Type': 'application/ipp' });
  #|           res.end(Buffer.from([2, 0, 0, 0, 0, 0, 0, 1, 3]));
  #|         }, 1000);
  #|         res.on('close', () => clearTimeout(timer));
  #|       } else {
  #|         if (req.url === '/target') probe.targetHits++;
  #|         const media = req.url === '/invalid-type' ? 'application/ipp;' : 'Application/IPP; charset=utf-8';
  #|         const headers = { 'Content-Type': media };
  #|         if (req.url === '/short') headers['Content-Length'] = '32';
  #|         res.writeHead(req.url === '/forbidden' ? 403 : 200, headers);
  #|         res.end(req.url === '/large' ? Buffer.alloc(16384, 120) : Buffer.from([2, 0, 0, 0, 0, 0, 0, 1, 3]));
  #|         if (req.url === '/short') res.socket.end();
  #|       }
  #|     });
  #|   });
  #|   await new Promise(resolve => probe.server.listen(0, '127.0.0.1', resolve));
  #|   return probe;
  #| }

///|
extern "js" fn RedirectProbe::uri(
  self : RedirectProbe,
  path : String,
) -> String =
  #| (probe, path) => `ipp://127.0.0.1:${probe.server.address().port}${path}`

///|
extern "js" fn RedirectProbe::target_hits(self : RedirectProbe) -> Int32 =
  #| probe => probe.targetHits

///|
extern "js" fn RedirectProbe::received_hex(self : RedirectProbe) -> String =
  #| probe => probe.received

///|
extern "js" fn RedirectProbe::requests(self : RedirectProbe) -> Int32 =
  #| probe => probe.requests

///|
extern "js" fn RedirectProbe::close(self : RedirectProbe) -> Unit =
  #| probe => { probe.server.close(); probe.server.closeAllConnections(); }

///|
async test "JS HTTP must not resend a document by following a 307 redirect" {
  let probe = start_redirect_probe().wait()
  defer probe.close()
  try
    HttpTransport::new().exchange(
      @ipp.PrinterUri::parse(probe.uri("/redirect")),
      b"private document",
      1024,
    )
  catch {
    error =>
      match error {
        HttpStatus(307) => ()
        _ => fail("unexpected redirect error: \{error}")
      }
  } noraise {
    _ => fail("redirect followed instead of refused")
  }
  assert_eq(probe.target_hits(), 0)
}

///|
async test "JS HTTP sends binary bytes and accepts the exact response size" {
  let probe = start_redirect_probe().wait()
  defer probe.close()
  let bytes = HttpTransport::new().exchange(
    @ipp.PrinterUri::parse(probe.uri("/ok")),
    b"\x00\xff\x03",
    9,
  )
  assert_eq(bytes, b"\x02\x00\x00\x00\x00\x00\x00\x01\x03")
  assert_eq(probe.received_hex(), "00ff03")
  assert_eq(probe.requests(), 1)
}

///|
async test "JS HTTP rejects oversized bodies invalid media types and HTTP errors" {
  let probe = start_redirect_probe().wait()
  defer probe.close()
  for path in ["/large", "/invalid-type", "/forbidden"] {
    try
      HttpTransport::new().exchange(
        @ipp.PrinterUri::parse(probe.uri(path)),
        b"",
        9,
      )
    catch {
      error =>
        match (path, error) {
          ("/large", ResponseTooLarge) => ()
          ("/invalid-type", UnexpectedContentType(_)) => ()
          ("/forbidden", HttpStatus(403)) => ()
          _ => fail("unexpected HTTP error: \{error}")
        }
    } noraise {
      _ => fail("invalid HTTP response accepted: \{path}")
    }
  }
  assert_eq(probe.requests(), 3)
}

///|
async test "JS HTTP refuses a truncated Content-Length response" {
  let probe = start_redirect_probe().wait()
  defer probe.close()
  try
    @async.with_timeout(3000, () => {
      HttpTransport::new().exchange(
        @ipp.PrinterUri::parse(probe.uri("/short")),
        b"",
        1024,
      )
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("truncated response accepted")
  }
}

///|
async test "JS HTTP aborts timed out requests and refuses cleartext authorization before IO" {
  let probe = start_redirect_probe().wait()
  defer probe.close()
  let endpoint = @ipp.PrinterUri::parse(probe.uri("/slow"))
  let authenticated = HttpTransport::new(authorization="Bearer private-token")
  try authenticated.exchange(endpoint, b"document", 1024) catch {
    error => assert_true(error is @ipp.Invalid(_))
  } noraise {
    _ => fail("cleartext credentials accepted")
  }
  assert_eq(probe.requests(), 0)
  let client = Client::new(
    endpoint.text(),
    HttpTransport::new(),
    timeout_ms=300,
  )
  try client.printer_attributes() catch {
    _ => ()
  } noraise {
    _ => fail("slow HTTP request did not time out")
  }
  assert_false(client.busy)
  assert_eq(probe.requests(), 1)
}
