///|
fn validate_string_value(tag : Int32, text : String) -> Unit raise IppError {
  let maximum = match tag {
    0x41 | 0x45 => 1023
    0x46 | 0x47 | 0x48 => 63
    _ => 255
  }
  if text.length() > maximum || encode_utf8(text).length() > maximum {
    raise Invalid("string exceeds the IPP value type's byte limit")
  }
  if tag >= 0x44 {
    if text.is_empty() {
      raise Invalid("empty ASCII attribute value")
    }
    for char in text {
      let n = char.to_int()
      if n >= 127 || (n < 32 && !(tag == 0x49 && n == 9)) {
        raise Invalid("attribute requires printable ASCII")
      }
    }
  }
  if tag == 0x49 && !valid_mime_type(text) {
    raise Invalid("invalid MIME media type")
  }
  if tag == 0x44 {
    // Registered keyword values include exceptions to the attribute-name
    // grammar, notably ipp-versions-supported's "1.1" and raster "sRGB_8".
    // Preserve their token bytes; option-specific readers enforce meanings.
    for char in text {
      let n = char.to_int()
      if !((n >= 97 && n <= 122) ||
        (n >= 65 && n <= 90) ||
        (n >= 48 && n <= 57) ||
        n == 45 ||
        n == 95 ||
        n == 46) {
        raise Invalid("invalid keyword token")
      }
    }
  }
}

///|
// RFC 8011 section 5.1 permits mixed syntaxes for union-valued attributes.
// Attribute-specific readers enforce their own types. Out-of-band values
// represent an entire unavailable attribute and must remain single-valued.
fn validate_value_set(values : Array[IppValue]) -> Unit raise IppError {
  if values.is_empty() ||
    (values.length() > 1 && values.any(value => value is OutOfBand(_))) {
    raise Invalid("attribute requires values or one out-of-band value")
  }
}

///|
fn decode_string_value(tag : Int32, bytes : Bytes) -> String raise IppError {
  let text = decode_utf8(bytes)
  validate_string_value(tag, text)
  text
}

///|
fn require_length(bytes : Bytes, expected : Int32) -> Unit raise IppError {
  if bytes.length() != expected {
    raise Invalid("value length \{bytes.length()}, expected \{expected}")
  }
}

///|
fn decode_localized(bytes : Bytes) -> (String, String) raise IppError {
  let reader = Reader::new(bytes)
  let language = decode_utf8(reader.length_bytes())
  let text = decode_utf8(reader.length_bytes())
  if reader.remaining() != 0 {
    raise Invalid("trailing data in localized text")
  }
  (language, text)
}

///|
fn decode_scalar(tag : Int32, bytes : Bytes) -> IppValue raise IppError {
  let reader = Reader::new(bytes)
  match tag {
    0x21 => {
      require_length(bytes, 4)
      Integer(reader.i32())
    }
    0x22 => {
      require_length(bytes, 1)
      let value = reader.byte()
      if value > 1 {
        raise Invalid("boolean value must be 0 or 1")
      }
      Boolean(value == 1)
    }
    0x23 => {
      require_length(bytes, 4)
      let value = reader.i32()
      if value < 1 {
        raise Invalid("enum value must be positive")
      }
      Enumeration(value)
    }
    0x30 => {
      if bytes.length() > 1023 {
        raise Invalid("octetString exceeds 1023 bytes")
      }
      Octets(bytes)
    }
    0x31 => {
      require_length(bytes, 11)
      let date : IppDateTime = {
        year: reader.u16(),
        month: reader.byte(),
        day: reader.byte(),
        hour: reader.byte(),
        minute: reader.byte(),
        second: reader.byte(),
        decisecond: reader.byte(),
        utc_direction: reader.byte(),
        utc_hours: reader.byte(),
        utc_minutes: reader.byte(),
      }
      date.validate()
      DateTime(date)
    }
    0x32 => {
      require_length(bytes, 9)
      let resolution : Resolution = {
        x: reader.i32(),
        y: reader.i32(),
        units: reader.byte(),
      }
      if resolution.x < 1 ||
        resolution.y < 1 ||
        (resolution.units != 3 && resolution.units != 4) {
        raise Invalid("invalid resolution")
      }
      ResolutionValue(resolution)
    }
    0x33 => {
      require_length(bytes, 8)
      let lower = reader.i32()
      let upper = reader.i32()
      if lower > upper {
        raise Invalid("reversed integer range")
      }
      Range(lower, upper)
    }
    0x35 => {
      let (language, text) = decode_localized(bytes)
      validate_string_value(0x48, language)
      validate_string_value(0x41, text)
      TextWithLanguage(language, text)
    }
    0x36 => {
      let (language, text) = decode_localized(bytes)
      validate_string_value(0x48, language)
      validate_string_value(0x42, text)
      NameWithLanguage(language, text)
    }
    0x41 => Text(decode_string_value(tag, bytes))
    0x42 => Name(decode_string_value(tag, bytes))
    0x44 => Keyword(decode_string_value(tag, bytes))
    0x45 => Uri(decode_string_value(tag, bytes))
    0x46 => UriScheme(decode_string_value(tag, bytes))
    0x47 => Charset(decode_string_value(tag, bytes))
    0x48 => Language(decode_string_value(tag, bytes))
    0x49 => MimeType(decode_string_value(tag, bytes))
    0x10 | 0x12 | 0x13 | 0x15 | 0x16 | 0x17 => {
      require_length(bytes, 0)
      OutOfBand(tag)
    }
    0x34 | 0x37 | 0x4a =>
      raise Invalid("collection structural tag outside collection")
    _ => {
      if tag < 0x10 || tag >= 0x7f {
        raise Unsupported("extended value tags")
      }
      Unknown(tag, bytes)
    }
  }
}

///|
fn encode_scalar(value : IppValue) -> Bytes raise IppError {
  let output = @buffer.Buffer()
  match value {
    Integer(n) => put_i32(output, n)
    Enumeration(n) => {
      if n < 1 {
        raise Invalid("enum must be positive")
      }
      put_i32(output, n)
    }
    Boolean(b) => put_byte(output, if b { 1 } else { 0 })
    Range(lower, upper) => {
      if lower > upper {
        raise Invalid("reversed range")
      }
      put_i32(output, lower)
      put_i32(output, upper)
    }
    ResolutionValue(resolution) => {
      if resolution.x < 1 ||
        resolution.y < 1 ||
        (resolution.units != 3 && resolution.units != 4) {
        raise Invalid("invalid resolution")
      }
      put_i32(output, resolution.x)
      put_i32(output, resolution.y)
      put_byte(output, resolution.units)
    }
    DateTime(date) => {
      date.validate()
      put_u16(output, date.year)
      put_byte(output, date.month)
      put_byte(output, date.day)
      put_byte(output, date.hour)
      put_byte(output, date.minute)
      put_byte(output, date.second)
      put_byte(output, date.decisecond)
      put_byte(output, date.utc_direction)
      put_byte(output, date.utc_hours)
      put_byte(output, date.utc_minutes)
    }
    Text(s)
    | Name(s)
    | Keyword(s)
    | Uri(s)
    | UriScheme(s)
    | Charset(s)
    | Language(s)
    | MimeType(s) => {
      validate_string_value(value.tag(), s)
      output.write_bytes(encode_utf8(s))
    }
    Octets(bytes) => {
      if bytes.length() > 1023 {
        raise Invalid("octetString exceeds 1023 bytes")
      }
      output.write_bytes(bytes)
    }
    Unknown(tag, bytes) => {
      if bytes.length() > 32767 {
        raise Invalid("unknown value exceeds wire length")
      }
      match decode_scalar(tag, bytes) {
        Unknown(_, _) => output.write_bytes(bytes)
        _ => raise Invalid("Unknown must use an unrecognized value tag")
      }
    }
    TextWithLanguage(language, text) | NameWithLanguage(language, text) => {
      validate_string_value(0x48, language)
      validate_string_value(if value.tag() == 0x35 { 0x41 } else { 0x42 }, text)
      put_length_bytes(output, encode_utf8(language))
      put_length_bytes(output, encode_utf8(text))
    }
    OutOfBand(tag) =>
      if tag != 0x10 &&
        tag != 0x12 &&
        tag != 0x13 &&
        tag != 0x15 &&
        tag != 0x16 &&
        tag != 0x17 {
        raise Invalid("invalid out-of-band tag")
      }
    Collection(_) => raise Invalid("collection must use collection encoder")
  }
  output.to_bytes()
}

///|
fn write_entry(
  output : @buffer.Buffer,
  tag : Int32,
  name : String,
  bytes : Bytes,
) -> Unit raise IppError {
  if tag < 0x10 || tag >= 0x7f {
    raise Unsupported("extended value tags")
  }
  put_byte(output, tag)
  put_length_bytes(output, encode_utf8(name))
  put_length_bytes(output, bytes)
}

///|
priv struct DecodeBudget {
  limits : DecodeLimits
  mut attributes : Int32
  mut values : Int32
  mut json_bytes : Int32
}

///|
fn DecodeBudget::json_size(
  self : DecodeBudget,
  count : Int32,
) -> Unit raise IppError {
  if count < 0 || count > self.limits.max_message_bytes - self.json_bytes {
    raise Limit("JSON message bytes")
  }
  self.json_bytes += count
}

///|
fn DecodeBudget::attribute(self : DecodeBudget) -> Unit raise IppError {
  if self.attributes >= self.limits.max_attributes {
    raise Limit("attribute count")
  }
  self.attributes += 1
}

///|
fn DecodeBudget::value(self : DecodeBudget) -> Unit raise IppError {
  if self.values >= self.limits.max_values {
    raise Limit("value count")
  }
  self.values += 1
}

///|
fn decode_collection(
  reader : Reader,
  budget : DecodeBudget,
  depth : Int32,
) -> Array[Attribute] raise IppError {
  if depth > budget.limits.max_collection_depth {
    raise Limit("collection nesting")
  }
  let members : Array[Attribute] = []
  let seen : Map[String, Bool] = Map([])
  let mut member_name = ""
  let mut member_values : Array[IppValue] = []
  while true {
    let tag = reader.byte()
    let name = reader.length_bytes()
    let bytes = reader.length_bytes()
    if name.length() != 0 {
      raise Invalid("collection entry name must be empty")
    }
    if tag == 0x37 {
      require_length(bytes, 0)
      if member_name != "" {
        if member_values.is_empty() {
          raise Invalid("collection member has no value")
        }
        members.push({ name: member_name, values: member_values, })
      }
      return members
    }
    if tag == 0x4a {
      if member_name != "" {
        if member_values.is_empty() {
          raise Invalid("collection member has no value")
        }
        members.push({ name: member_name, values: member_values, })
      }
      member_name = decode_utf8(bytes)
      if !valid_attribute_name(member_name) {
        raise Invalid("invalid collection member name")
      }
      if seen.contains(member_name) {
        raise Invalid("duplicate collection member")
      }
      seen[member_name] = true
      budget.attribute()
      member_values = []
    } else {
      if member_name == "" {
        raise Invalid("collection value before member name")
      }
      budget.value()
      let value = if tag == 0x34 {
        require_length(bytes, 0)
        IppValue::Collection(decode_collection(reader, budget, depth + 1))
      } else {
        decode_scalar(tag, bytes)
      }
      if !member_values.is_empty() &&
        (member_values[0] is OutOfBand(_) || value is OutOfBand(_)) {
        raise Invalid("out-of-band collection member must have one value")
      }
      member_values.push(value)
    }
  } nobreak {
    raise Invalid("unterminated collection")
  }
}

///|
fn encode_collection(
  output : @buffer.Buffer,
  members : Array[Attribute],
  budget : DecodeBudget,
  depth : Int32,
) -> Unit raise IppError {
  if depth > budget.limits.max_collection_depth {
    raise Limit("collection nesting")
  }
  let seen : Map[String, Bool] = Map([])
  for field in members {
    budget.attribute()
    if !valid_attribute_name(field.name) || field.values.is_empty() {
      raise Invalid("invalid collection member")
    }
    validate_value_set(field.values)
    if seen.contains(field.name) {
      raise Invalid("duplicate collection member")
    }
    seen[field.name] = true
    write_entry(output, 0x4a, "", encode_utf8(field.name))
    for value in field.values {
      budget.value()
      match value {
        Collection(children) => {
          write_entry(output, 0x34, "", b"")
          encode_collection(output, children, budget, depth + 1)
        }
        _ => write_entry(output, value.tag(), "", encode_scalar(value))
      }
      if output.length() > budget.limits.max_message_bytes {
        raise Limit("message bytes")
      }
    }
  }
  write_entry(output, 0x37, "", b"")
}
