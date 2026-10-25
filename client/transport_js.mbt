///|
#external
priv type FetchResponse

///|
extern "js" fn fetch_ipp(
  url : String,
  body : Bytes,
  authorization : String,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[FetchResponse] =
  #| (url, body, authorization, signal) => {
  #|   const headers = { 'Content-Type': 'application/ipp', Accept: 'application/ipp' };
  #|   if (authorization !== '') headers.Authorization = authorization;
  #|   return fetch(url, { method: 'POST', body, headers, signal,
  #|     redirect: 'manual', credentials: 'omit', cache: 'no-store' });
  #| }

///|
extern "js" fn FetchResponse::status(self : FetchResponse) -> Int32 =
  #| response => response.status

///|
extern "js" fn FetchResponse::content_type(self : FetchResponse) -> String =
  #| response => response.headers.get('Content-Type') ?? ''

///|
extern "js" fn FetchResponse::body(
  self : FetchResponse,
) -> @js_async.JsReadableStream =
  #| response => response.body ?? new ReadableStream({ start(controller) { controller.close(); } })

///|
async fn exchange_http(
  endpoint : @ipp.PrinterUri,
  request : Bytes,
  maximum : Int32,
  authorization : String?,
) -> Bytes {
  let controller = @js_async.AbortController::new()
  defer controller.abort()
  let response = fetch_ipp(
    endpoint.http_url(),
    request,
    authorization.unwrap_or(""),
    controller.signal(),
  ).wait(abort_controller=controller)
  let stream = @js_async.ReadableStream::from_js(response.body())
  defer stream.close()
  if response.status() != 200 {
    // A browser can expose a manual redirect as opaque status 0. It is still
    // refused; neither the document nor the explicit credentials are resent.
    raise HttpStatus(response.status())
  }
  let content_type = response.content_type()
  let media_type = match content_type.split_once(";") {
    Some((media, _)) => media.trim().to_owned().to_lower()
    None => content_type.trim().to_owned().to_lower()
  }
  if media_type != "application/ipp" || !@ipp.valid_mime_type(content_type) {
    raise UnexpectedContentType(content_type)
  }
  let buffer = @buffer.Buffer()
  while true {
    match stream.read_some(max_len=8192) {
      None => break
      Some(bytes) => {
        if bytes.length() > maximum - buffer.length() {
          raise ResponseTooLarge
        }
        buffer.write_bytes(bytes)
      }
    }
  }
  buffer.to_bytes()
}
