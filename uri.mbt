///|
pub(all) struct PrinterUri {
  scheme : String
  host : String
  port : Int
  path : String
  ipv6 : Bool
} derive(Eq, Debug)

///|
pub extend PrinterUri with Eq::{equal, not_equal}

///|
pub extend PrinterUri with @debug.Debug::{to_repr}

///|
fn parse_decimal(text : String, maximum : Int) -> Int raise IppError {
  if text.is_empty() {
    raise Invalid("empty integer")
  }
  let mut value = 0
  for char in text.to_array() {
    let digit = char.to_int() - 48
    if digit < 0 || digit > 9 {
      raise Invalid("invalid integer")
    }
    if value > (maximum - digit) / 10 {
      raise Invalid("integer exceeds maximum \{maximum}")
    }
    value = value * 10 + digit
  }
  value
}

///|
fn string_slice(text : String, start : Int, end : Int) -> String {
  text.exact_view(start~, end~).to_owned()
}

///|
pub fn PrinterUri::parse(text : String) -> PrinterUri raise IppError {
  if text.length() > 1023 {
    raise Invalid("printer URI exceeds 1023 characters")
  }
  for char in text.to_array() {
    if char.to_int() <= 32 || char.to_int() >= 127 {
      raise Invalid("URI requires escaped ASCII characters")
    }
  }
  let (scheme_view, remainder_view) = match text.split_once("://") {
    Some(parts) => parts
    None => raise Invalid("URI must include scheme and authority")
  }
  let scheme = scheme_view.to_owned()
  if scheme != "ipp" && scheme != "ipps" {
    raise Invalid("printer URI scheme must be ipp or ipps")
  }
  let remainder = remainder_view.to_owned()
  let slash = match remainder.find("/") {
    Some(index) => index
    None => remainder.length()
  }
  let authority = string_slice(remainder, 0, slash)
  let path = if slash == remainder.length() {
    "/"
  } else {
    string_slice(remainder, slash, remainder.length())
  }
  if authority.is_empty() || authority.contains("@") {
    raise Invalid("empty host or URI userinfo")
  }
  if path.contains("#") || path.contains("?") || path.contains("\\") {
    raise Invalid(
      "printer URI path must not contain query, fragment or backslash",
    )
  }
  let mut host = ""
  let mut port = 631
  let ipv6 = authority.has_prefix("[")
  if ipv6 {
    let closing = match authority.find("]") {
      Some(index) => index
      None => raise Invalid("unterminated IPv6 host")
    }
    host = string_slice(authority, 1, closing)
    if !host.contains(":") || host.is_empty() {
      raise Invalid("invalid IPv6 host")
    }
    let suffix = string_slice(authority, closing + 1, authority.length())
    if suffix != "" {
      if !suffix.has_prefix(":") {
        raise Invalid("unexpected data after IPv6 host")
      }
      port = parse_decimal(string_slice(suffix, 1, suffix.length()), 65535)
    }
  } else {
    match authority.split_once(":") {
      Some((hostname, port_text)) => {
        host = hostname.to_owned()
        port = parse_decimal(port_text.to_owned(), 65535)
      }
      None => host = authority
    }
    for char in host.to_array() {
      let n = char.to_int()
      if !((n >= 48 && n <= 57) ||
        (n >= 65 && n <= 90) ||
        (n >= 97 && n <= 122) ||
        n == 45 ||
        n == 46) {
        raise Invalid("invalid hostname")
      }
    }
  }
  if host.is_empty() || port < 1 {
    raise Invalid("host and port must not be empty")
  }
  let mut i = 0
  while i < path.length() {
    if path[i].to_int() == 37 {
      if i + 2 >= path.length() ||
        hex_nibble(path[i + 1]) is None ||
        hex_nibble(path[i + 2]) is None {
        raise Invalid("invalid percent escape")
      }
      i += 3
    } else {
      i += 1
    }
  }
  { scheme, host, port, path, ipv6, }
}

///|
pub fn PrinterUri::authority(self : PrinterUri) -> String {
  let host = if self.ipv6 { "[\{self.host}]" } else { self.host }
  "\{host}:\{self.port}"
}

///|
pub fn PrinterUri::text(self : PrinterUri) -> String {
  "\{self.scheme}://\{self.authority()}\{self.path}"
}

///|
pub fn PrinterUri::http_url(self : PrinterUri) -> String {
  let scheme = if self.scheme == "ipps" { "https" } else { "http" }
  "\{scheme}://\{self.authority()}\{self.path}"
}

///|
pub fn PrinterUri::secure(self : PrinterUri) -> Bool {
  self.scheme == "ipps"
}
