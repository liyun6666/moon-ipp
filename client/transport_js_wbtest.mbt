///|
#external
priv type RedirectProbe

///|
extern "js" fn start_redirect_probe() -> @js_async.Promise[RedirectProbe] =
  #| async () => {
  #|   const { createServer } = await import('node:http');
  #|   const probe = { server: null, targetHits: 0, starts: 0, received: '', requests: 0, namedMedia: false };
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
  #|         let body = req.url === '/large' ? Buffer.alloc(16384, 120) : Buffer.from([2, 0, 0, 0, 0, 0, 0, 1, 3]);
  #|         if (req.url === '/client' || req.url === '/media') {
  #|           const attribute = (tag, name, value) => {
  #|             const n = Buffer.from(name), v = Buffer.from(value), a = Buffer.alloc(5 + n.length + v.length);
  #|             a[0] = tag; a.writeInt16BE(n.length, 1); n.copy(a, 3);
  #|             a.writeInt16BE(v.length, 3 + n.length); v.copy(a, 5 + n.length); return a;
  #|           };
  #|           const header = Buffer.from([2, 0, 0, 0, 0, 0, 0, 1, 1]);
  #|           header.writeInt32BE(Buffer.concat(chunks).readInt32BE(4), 4);
  #|           const parts = [header,
  #|             attribute(0x47, 'attributes-charset', 'utf-8'),
  #|             attribute(0x48, 'attributes-natural-language', 'en')];
  #|           const request = Buffer.concat(chunks), operation = request.readInt16BE(2);
  #|           if (req.url === '/media' && operation === 2) {
  #|             for (let i = 8; i < request.length;) {
  #|               const tag = request[i++];
  #|               if (tag === 3) break;
  #|               if (tag < 0x10) continue;
  #|               const nl = request.readInt16BE(i); i += 2;
  #|               const name = request.subarray(i, i + nl).toString('utf8'); i += nl;
  #|               const vl = request.readInt16BE(i); i += 2;
  #|               if (name === 'media') probe.namedMedia = tag === 0x42 && request.subarray(i, i + vl).toString('utf8') === '办公室专用 A4';
  #|               i += vl;
  #|             }
  #|             parts.push(Buffer.from([2]), attribute(0x21, 'job-id', [0, 0, 0, 27]), attribute(0x23, 'job-state', [0, 0, 0, 9]));
  #|           } else {
  #|             parts.push(Buffer.from([4]), attribute(0x42, 'printer-name', 'JS loopback'));
  #|             if (req.url === '/media') parts.push(
  #|               attribute(0x42, 'media-default', '办公室专用 A4'),
  #|               attribute(0x42, 'media-supported', '办公室专用 A4'),
  #|               attribute(0x49, 'document-format-supported', 'application/pdf'),
  #|               attribute(0x23, 'operations-supported', [0, 0, 0, 2]));
  #|           }
  #|           parts.push(Buffer.from([3]));
  #|           body = Buffer.concat(parts);
  #|         }
  #|         res.end(body);
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
extern "js" fn RedirectProbe::named_media(self : RedirectProbe) -> Bool =
  #| probe => probe.namedMedia

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
    @async.with_timeout(
      3000,
      () => {
        HttpTransport::new().exchange(
          @ipp.PrinterUri::parse(probe.uri("/short")),
          b"",
          1024,
        )
      },
      error=@ipp.Invalid("HTTP probe timeout"),
    )
  catch {
    @ipp.Invalid("HTTP probe timeout") =>
      fail("truncated response hung until timeout")
    _ => assert_eq(probe.requests(), 1)
  } noraise {
    _ => fail("truncated response accepted")
  }
}

///|
async test "JS client validates an independently encoded real HTTP response" {
  let probe = start_redirect_probe().wait()
  defer probe.close()
  let client = Client::new(probe.uri("/client"), HttpTransport::new())
  let capabilities = client.capabilities()
  assert_eq(capabilities.name(), "JS loopback")
  assert_eq(probe.requests(), 1)
  assert_false(client.busy)
}

///|
async test "JS custom stock defaults preflight and print agree with independent wire parsing" {
  let probe = start_redirect_probe().wait()
  defer probe.close()
  let client = Client::new(probe.uri("/media"), HttpTransport::new())
  let capabilities = client.capabilities()
  let options = capabilities.default_options("Named stock", "application/pdf")
  assert_eq(options.media, Some("办公室专用 A4"))
  let job = client.print_job(options, b"pdf")
  assert_eq(job.id, 27)
  assert_true(probe.named_media())
  assert_eq(probe.requests(), 3)
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
