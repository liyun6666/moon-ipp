///|
fn mime_token_character(char : UInt16) -> Bool {
  let n = char.to_int()
  n > 32 &&
  n < 127 &&
  !"()<>@,;:\\\"/[]?=".contains(char.to_char().unwrap().to_string())
}

///|
fn mime_token_end(text : String, start : Int32) -> Int32 {
  for end = start
      end < text.length() && mime_token_character(text[end])
      end = end + 1 {
    continue
  } nobreak {
    end
  }
}

///|
fn skip_mime_space(text : String, start : Int32) -> Int32 {
  for end = start
      end < text.length() && (text[end] == ' ' || text[end] == '\t')
      end = end + 1 {
    continue
  } nobreak {
    end
  }
}

///|
fn parse_mime_type(text : String) -> (String, Map[String, String])? {
  if text.length() < 3 || text.length() > 255 {
    return None
  }
  for char in text {
    let n = char.to_int()
    if (n < 32 && n != 9) || n >= 127 {
      return None
    }
  }
  let start = skip_mime_space(text, 0)
  let slash = mime_token_end(text, start)
  if slash == start || slash >= text.length() || text[slash] != '/' {
    return None
  }
  let subtype_end = mime_token_end(text, slash + 1)
  if subtype_end == slash + 1 {
    return None
  }
  let base = string_slice(text, start, subtype_end).to_lower()
  if base.contains("*") {
    return None
  }
  let parameters : Map[String, String] = Map([])
  let mut index = subtype_end
  while true {
    index = skip_mime_space(text, index)
    if index == text.length() {
      return Some((base, parameters))
    }
    if text[index] != ';' {
      return None
    }
    let name_start = skip_mime_space(text, index + 1)
    let name_end = mime_token_end(text, name_start)
    if name_end == name_start {
      return None
    }
    let name = string_slice(text, name_start, name_end).to_lower()
    if parameters.contains(name) {
      return None
    }
    index = skip_mime_space(text, name_end)
    if index >= text.length() || text[index] != '=' {
      return None
    }
    index = skip_mime_space(text, index + 1)
    if index >= text.length() {
      return None
    }
    let value = if text[index] == '"' {
      index += 1
      let builder = StringBuilder()
      let mut closed = false
      while index < text.length() {
        let char = text[index]
        index += 1
        if char == '"' {
          closed = true
          break
        }
        if char == '\\' {
          if index == text.length() {
            return None
          }
          builder.write_char(text[index].to_char().unwrap())
          index += 1
        } else {
          builder.write_char(char.to_char().unwrap())
        }
      }
      if !closed {
        return None
      }
      builder.to_string()
    } else {
      let end = mime_token_end(text, index)
      if end == index {
        return None
      }
      let value = string_slice(text, index, end)
      index = end
      value
    }
    parameters[name] = if name == "charset" { value.to_lower() } else { value }
  } nobreak {
    None
  }
}

///|
/// Accept registered media types with optional MIME parameters, within IPP's
/// 255-byte ASCII bound. Wildcard ranges and duplicate parameters are rejected.
/// ```mbt check
/// test {
///   assert_true(@lib.valid_mime_type("text/plain; charset=UTF-8"))
///   assert_false(@lib.valid_mime_type("text/*"))
/// }
/// ```
pub fn valid_mime_type(text : String) -> Bool {
  parse_mime_type(text) is Some(_)
}

///|
fn mime_types_equal(left : String, right : String) -> Bool {
  match (parse_mime_type(left), parse_mime_type(right)) {
    (Some(a), Some(b)) => a == b
    _ => false
  }
}
