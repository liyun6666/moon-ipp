///|
pub fn valid_attribute_name(name : String) -> Bool {
  if name.length() < 1 || name.length() > 255 {
    return false
  }
  for char in name.to_array() {
    let n = char.to_int()
    if !((n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 95 ||
      n == 46) {
      return false
    }
  }
  true
}

///|
fn valid_group_tag(tag : Int) -> Bool {
  tag == 0x01 || tag == 0x02 || (tag >= 0x04 && tag <= 0x0a)
}

///|
pub fn decode(
  bytes : Bytes,
  limits? : DecodeLimits = DecodeLimits::defaults(),
) -> Message raise IppError {
  limits.validate()
  if bytes.length() < 9 {
    raise Truncated(0, 9)
  }
  let reader = Reader::new(bytes)
  let version = Version::new(reader.byte(), reader.byte())
  let code = reader.u16()
  let request_id = reader.i32()
  if request_id < 1 {
    raise Invalid("request-id must be positive")
  }
  let budget : DecodeBudget = { limits, attributes: 0, values: 0, }
  let groups : Array[Group] = []
  let mut group_tag = 0
  let mut attributes : Array[Attribute] = []
  while true {
    if reader.offset > limits.max_message_bytes {
      raise Limit("message bytes")
    }
    let tag = reader.byte()
    if tag == 0x03 {
      if group_tag != 0 {
        groups.push({ tag: group_tag, attributes, })
      }
      if reader.offset > limits.max_message_bytes {
        raise Limit("message bytes")
      }
      if reader.remaining() > limits.max_document_bytes {
        raise Limit("document bytes")
      }
      let document = reader.bytes(reader.remaining())
      return { version, code, request_id, groups, document, }
    }
    if tag < 0x10 {
      if !valid_group_tag(tag) {
        raise Invalid("invalid attribute group tag \{tag}")
      }
      if group_tag != 0 {
        groups.push({ tag: group_tag, attributes, })
      }
      group_tag = tag
      attributes = []
      continue
    }
    if group_tag == 0 {
      raise Invalid("attribute before group delimiter")
    }
    let name = decode_utf8(reader.length_bytes())
    let payload = reader.length_bytes()
    budget.value()
    let value = if tag == 0x34 {
      require_length(payload, 0)
      IppValue::Collection(decode_collection(reader, budget, 1))
    } else {
      decode_scalar(tag, payload)
    }
    if name == "" {
      if attributes.is_empty() {
        raise Invalid("additional value without an attribute")
      }
      let last = attributes[attributes.length() - 1]
      if last.values[0].tag() != value.tag() {
        raise Invalid("attribute mixes value tags")
      }
      last.values.push(value)
    } else {
      budget.attribute()
      if !valid_attribute_name(name) {
        raise Invalid("invalid attribute name")
      }
      if attributes.any(fn(attribute) { attribute.name == name }) {
        raise Invalid("duplicate attribute within group")
      }
      attributes.push({ name, values: [value], })
    }
  } nobreak {
    raise Invalid("unterminated message")
  }
}

///|
pub fn encode(
  message : Message,
  limits? : DecodeLimits = DecodeLimits::defaults(),
) -> Bytes raise IppError {
  limits.validate()
  let _ = Version::new(message.version.major, message.version.minor)
  if message.request_id < 1 {
    raise Invalid("request-id must be positive")
  }
  if message.document.length() > limits.max_document_bytes {
    raise Limit("document bytes")
  }
  let output = @buffer.Buffer()
  let budget : DecodeBudget = { limits, attributes: 0, values: 0, }
  put_byte(output, message.version.major)
  put_byte(output, message.version.minor)
  put_u16(output, message.code)
  put_i32(output, message.request_id)
  for group in message.groups {
    if !valid_group_tag(group.tag) {
      raise Invalid("invalid group tag")
    }
    put_byte(output, group.tag)
    let seen : Map[String, Bool] = Map([])
    for attribute in group.attributes {
      budget.attribute()
      if !valid_attribute_name(attribute.name) || attribute.values.is_empty() {
        raise Invalid("invalid attribute")
      }
      if seen.contains(attribute.name) {
        raise Invalid("duplicate attribute within group")
      }
      seen[attribute.name] = true
      for index, value in attribute.values {
        budget.value()
        if value.tag() != attribute.values[0].tag() {
          raise Invalid("attribute mixes value tags")
        }
        let name = if index == 0 { attribute.name } else { "" }
        match value {
          Collection(members) => {
            write_entry(output, 0x34, name, b"")
            encode_collection(output, members, budget, 1)
          }
          _ => write_entry(output, value.tag(), name, encode_scalar(value))
        }
      }
      if output.length() > limits.max_message_bytes {
        raise Limit("message bytes")
      }
    }
  }
  put_byte(output, 0x03)
  if output.length() > limits.max_message_bytes {
    raise Limit("message bytes")
  }
  output.write_bytes(message.document)
  output.to_bytes()
}
