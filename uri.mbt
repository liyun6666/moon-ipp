///|
pub(all) struct PrinterUri {
  scheme : String
  host : String
  port : Int32
  path : String
  ipv6 : Bool
} derive(Eq, Debug)

///|
pub extend PrinterUri with Eq::{equal, not_equal}

///|
pub extend PrinterUri with @debug.Debug::{to_repr}

///|
fn parse_decimal(text : String, maximum : Int32) -> Int32 raise IppError {
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
fn string_slice(text : String, start : Int32, end : Int32) -> String {
  text.exact_view(start~, end~).to_owned()
}

///|
fn valid_ipv4_literal(text : String) -> Bool {
  let parts = text.split(".").to_array()
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    if part.is_empty() ||
      part.length() > 3 ||
      (part.length() > 1 && part[0] == '0') {
      return false
    }
    let mut number = 0
    for char in part {
      let digit = char.to_int() - 48
      if digit < 0 || digit > 9 {
        return false
      }
      number = number * 10 + digit
    }
    if number > 255 {
      return false
    }
  }
  true
}

///|
fn ipv6_units(text : String, allow_ipv4 : Bool) -> Int32? {
  if text.is_empty() {
    return Some(0)
  }
  let parts = text.split(":").to_array()
  let mut count = 0
  for index, part in parts {
    if part.contains(".") {
      if !allow_ipv4 ||
        index != parts.length() - 1 ||
        !valid_ipv4_literal(part.to_owned()) {
        return None
      }
      count += 2
    } else {
      if part.is_empty() || part.length() > 4 {
        return None
      }
      let word = part.to_owned()
      for i in 0..<word.length() {
        if hex_nibble(word[i]) is None {
          return None
        }
      }
      count += 1
    }
  }
  Some(count)
}

///|
fn valid_ipv6_literal(host : String) -> Bool {
  match host.split_once("::") {
    Some((left, right)) => {
      if right.contains("::") {
        return false
      }
      match
        (ipv6_units(left.to_owned(), false), ipv6_units(right.to_owned(), true)) {
        (Some(a), Some(b)) => a + b < 8
        _ => false
      }
    }
    None => ipv6_units(host, true) == Some(8)
  }
}

///|
fn valid_dns_host(host : String) -> Bool {
  let name = if host.has_suffix(".") {
    string_slice(host, 0, host.length() - 1)
  } else {
    host
  }
  if name.is_empty() || name.length() > 253 {
    return false
  }
  for label in name.split(".") {
    if label.is_empty() ||
      label.length() > 63 ||
      label.has_prefix("-") ||
      label.has_suffix("-") {
      return false
    }
    for char in label {
      let n = char.to_int()
      if !((n >= 48 && n <= 57) ||
        (n >= 65 && n <= 90) ||
        (n >= 97 && n <= 122) ||
        n == 45) {
        return false
      }
    }
  }
  true
}

///|
fn valid_path_character(char : UInt16) -> Bool {
  let n = char.to_int()
  (n >= 48 && n <= 57) ||
  (n >= 65 && n <= 90) ||
  (n >= 97 && n <= 122) ||
  "-._~!$&'()*+,;=:@/".contains(char.to_char().unwrap().to_string())
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
  let scheme = scheme_view.to_owned().to_lower()
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
    if !valid_ipv6_literal(host) {
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
    if !valid_dns_host(host) {
      raise Invalid("invalid hostname")
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
      if !valid_path_character(path[i]) {
        raise Invalid("URI path contains an unescaped reserved character")
      }
      i += 1
    }
  }
  let result : PrinterUri = { scheme, host: host.to_lower(), port, path, ipv6, }
  if result.text().length() > 1023 {
    raise Invalid("normalized printer URI exceeds 1023 characters")
  }
  result
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
