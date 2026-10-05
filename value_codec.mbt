///|
fn require_length(bytes : Bytes, expected : Int) -> Unit raise IppError {
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
fn decode_scalar(tag : Int, bytes : Bytes) -> IppValue raise IppError {
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
    0x30 => Octets(bytes)
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
      TextWithLanguage(language, text)
    }
    0x36 => {
      let (language, text) = decode_localized(bytes)
      NameWithLanguage(language, text)
    }
    0x41 => Text(decode_utf8(bytes))
    0x42 => Name(decode_utf8(bytes))
    0x44 => Keyword(decode_utf8(bytes))
    0x45 => Uri(decode_utf8(bytes))
    0x46 => UriScheme(decode_utf8(bytes))
    0x47 => Charset(decode_utf8(bytes))
    0x48 => Language(decode_utf8(bytes))
    0x49 => MimeType(decode_utf8(bytes))
    0x10 | 0x12 | 0x13 | 0x15 | 0x16 | 0x17 => {
      require_length(bytes, 0)
      OutOfBand(tag)
    }
    0x34 | 0x37 | 0x4a =>
      raise Invalid("collection structural tag outside collection")
    _ => {
      if tag < 0x10 || tag > 0x7f {
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
    | MimeType(s) => output.write_bytes(encode_utf8(s))
    Octets(bytes) | Unknown(_, bytes) => output.write_bytes(bytes)
    TextWithLanguage(language, text) | NameWithLanguage(language, text) => {
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
  tag : Int,
  name : String,
  bytes : Bytes,
) -> Unit raise IppError {
  if tag < 0x10 || tag > 0x7f {
    raise Unsupported("extended value tags")
  }
  put_byte(output, tag)
  put_length_bytes(output, encode_utf8(name))
  put_length_bytes(output, bytes)
}

///|
priv struct DecodeBudget {
  limits : DecodeLimits
  mut attributes : Int
  mut values : Int
}

///|
fn DecodeBudget::attribute(self : DecodeBudget) -> Unit raise IppError {
  self.attributes += 1
  if self.attributes > self.limits.max_attributes {
    raise Limit("attribute count")
  }
}

///|
fn DecodeBudget::value(self : DecodeBudget) -> Unit raise IppError {
  self.values += 1
  if self.values > self.limits.max_values {
    raise Limit("value count")
  }
}

///|
fn decode_collection(
  reader : Reader,
  budget : DecodeBudget,
  depth : Int,
) -> Array[Attribute] raise IppError {
  if depth > budget.limits.max_collection_depth {
    raise Limit("collection nesting")
  }
  let members : Array[Attribute] = []
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
      if member_values.length() > 0 && member_values[0].tag() != value.tag() {
        raise Invalid("collection member mixes value tags")
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
  depth : Int,
) -> Unit raise IppError {
  if depth > budget.limits.max_collection_depth {
    raise Limit("collection nesting")
  }
  for field in members {
    budget.attribute()
    if !valid_attribute_name(field.name) || field.values.is_empty() {
      raise Invalid("invalid collection member")
    }
    write_entry(output, 0x4a, "", encode_utf8(field.name))
    for value in field.values {
      budget.value()
      if value.tag() != field.values[0].tag() {
        raise Invalid("collection member mixes value tags")
      }
      match value {
        Collection(children) => {
          write_entry(output, 0x34, "", b"")
          encode_collection(output, children, budget, depth + 1)
        }
        _ => write_entry(output, value.tag(), "", encode_scalar(value))
      }
    }
  }
  write_entry(output, 0x37, "", b"")
}
