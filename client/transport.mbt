///|
pub(all) suberror ClientError {
  HttpStatus(Int)
  UnexpectedContentType(String)
  ResponseTooLarge
  ConcurrentRequest
  SubmissionUncertain(String)
  JobWaitExpired(Int)
} derive(@debug.Debug)

///|
pub extend ClientError with @debug.Debug::{to_repr}

///|
pub trait Transport {
  async fn exchange(Self, @ipp.PrinterUri, Bytes, Int) -> Bytes
}

///|
pub struct HttpTransport {
  authorization : String?
}

///|
pub extend HttpTransport with Transport::{exchange}

///|
pub fn HttpTransport::new(
  authorization? : String,
) -> HttpTransport raise @ipp.IppError {
  match authorization {
    Some(value) =>
      if value.is_empty() || value.contains("\r") || value.contains("\n") {
        raise @ipp.Invalid("invalid authorization header")
      }
    None => ()
  }
  { authorization, }
}

///|
pub impl Transport for HttpTransport with fn exchange(
  self,
  endpoint,
  request,
  maximum,
) {
  if maximum < 9 {
    raise @ipp.Invalid("response limit must be at least 9")
  }
  let connection = @http.Client(endpoint.http_url())
  defer connection.close()
  let headers : Map[@http.CaseInsensitiveString, String] = Map([
    (@http.CaseInsensitiveString("Content-Type"), "application/ipp"),
    (@http.CaseInsensitiveString("Accept"), "application/ipp"),
    (@http.CaseInsensitiveString("User-Agent"), "moon-ipp/0.1.0"),
  ])
  match self.authorization {
    Some(value) => {
      if !endpoint.secure() {
        raise @ipp.Invalid("authorization requires ipps transport")
      }
      headers[@http.CaseInsensitiveString("Authorization")] = value
    }
    None => ()
  }
  let response = connection.post(endpoint.path, request, extra_headers=headers)
  if response.code != 200 {
    raise HttpStatus(response.code)
  }
  let content_type = match
    response.headers.get(@http.CaseInsensitiveString("Content-Type")) {
    Some(value) => value.to_lower()
    None => ""
  }
  let media_type = match content_type.split_once(";") {
    Some((media, _)) => media.trim().to_owned()
    None => content_type
  }
  if media_type != "application/ipp" {
    raise UnexpectedContentType(content_type)
  }
  let buffer = @buffer.Buffer()
  while true {
    match connection.read_some(max_len=8192) {
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
