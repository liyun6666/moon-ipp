///|
fn json_int(value : Int) -> Json {
  Json::number(value.to_double())
}

///|
fn json_field(json : Json, field : String) -> Json raise IppError {
  match json {
    Object(fields) =>
      match fields.get(field) {
        Some(value) => value
        None => raise Invalid("missing JSON field: \{field}")
      }
    _ => raise Invalid("JSON object expected")
  }
}

///|
fn json_as_int(json : Json) -> Int raise IppError {
  match json {
    Number(number, ..) => {
      if number < -2147483648.0 ||
        number > 2147483647.0 ||
        number != number.floor() {
        raise Invalid("JSON integer out of range")
      }
      number.to_int()
    }
    _ => raise Invalid("JSON integer expected")
  }
}

///|
fn json_as_string(json : Json) -> String raise IppError {
  match json {
    String(text) => text
    _ => raise Invalid("JSON string expected")
  }
}

///|
fn json_as_array(json : Json) -> Array[Json] raise IppError {
  match json {
    Array(values) => values
    _ => raise Invalid("JSON array expected")
  }
}

///|
fn json_get_int(json : Json, field : String) -> Int raise IppError {
  json_as_int(json_field(json, field))
}

///|
fn json_get_string(json : Json, field : String) -> String raise IppError {
  json_as_string(json_field(json, field))
}

///|
pub fn IppValue::to_json(self : IppValue) -> Json {
  let value : Json = match self {
    Integer(n) | Enumeration(n) => json_int(n)
    Boolean(b) => Json::boolean(b)
    Range(lower, upper) =>
      { "lower": json_int(lower), "upper": json_int(upper) }
    ResolutionValue(resolution) =>
      {
        "x": json_int(resolution.x),
        "y": json_int(resolution.y),
        "units": json_int(resolution.units),
      }
    DateTime(date) =>
      {
        "year": json_int(date.year),
        "month": json_int(date.month),
        "day": json_int(date.day),
        "hour": json_int(date.hour),
        "minute": json_int(date.minute),
        "second": json_int(date.second),
        "decisecond": json_int(date.decisecond),
        "utc_direction": json_int(date.utc_direction),
        "utc_hours": json_int(date.utc_hours),
        "utc_minutes": json_int(date.utc_minutes),
      }
    Text(text)
    | Name(text)
    | Keyword(text)
    | Uri(text)
    | UriScheme(text)
    | Charset(text)
    | Language(text)
    | MimeType(text) => Json::string(text)
    Octets(bytes) | Unknown(_, bytes) => Json::string(bytes_to_hex(bytes))
    TextWithLanguage(language, text) | NameWithLanguage(language, text) =>
      { "language": Json::string(language), "text": Json::string(text) }
    Collection(members) =>
      Json::array(members.map(fn(field) { field.to_json() }))
    OutOfBand(_) => Json::null()
  }
  {
    "tag": json_int(self.tag()),
    "type": Json::string(value_tag_name(self.tag())),
    "value": value,
  }
}

///|
pub fn Attribute::to_json(self : Attribute) -> Json {
  {
    "name": Json::string(self.name),
    "values": Json::array(self.values.map(fn(value) { value.to_json() })),
  }
}

///|
pub fn Group::to_json(self : Group) -> Json {
  {
    "tag": json_int(self.tag),
    "name": Json::string(group_name(self.tag)),
    "attributes": Json::array(
      self.attributes.map(fn(attribute) { attribute.to_json() }),
    ),
  }
}

///|
pub fn Message::to_json(self : Message) -> Json {
  {
    "version": {
      "major": json_int(self.version.major),
      "minor": json_int(self.version.minor),
    },
    "code": json_int(self.code),
    "request_id": json_int(self.request_id),
    "groups": Json::array(self.groups.map(fn(group) { group.to_json() })),
    "document_hex": Json::string(bytes_to_hex(self.document)),
  }
}

///|
fn value_from_json(
  json : Json,
  budget : DecodeBudget,
  depth : Int,
) -> IppValue raise IppError {
  budget.value()
  let tag = json_get_int(json, "tag")
  let value = json_field(json, "value")
  match tag {
    0x21 => Integer(json_as_int(value))
    0x22 =>
      match value {
        True => Boolean(true)
        False => Boolean(false)
        _ => raise Invalid("boolean JSON value expected")
      }
    0x23 => {
      let code = json_as_int(value)
      if code < 1 {
        raise Invalid("enum must be positive")
      }
      Enumeration(code)
    }
    0x30 => Octets(bytes_from_hex(json_as_string(value)))
    0x31 => {
      let date : IppDateTime = {
        year: json_get_int(value, "year"),
        month: json_get_int(value, "month"),
        day: json_get_int(value, "day"),
        hour: json_get_int(value, "hour"),
        minute: json_get_int(value, "minute"),
        second: json_get_int(value, "second"),
        decisecond: json_get_int(value, "decisecond"),
        utc_direction: json_get_int(value, "utc_direction"),
        utc_hours: json_get_int(value, "utc_hours"),
        utc_minutes: json_get_int(value, "utc_minutes"),
      }
      date.validate()
      DateTime(date)
    }
    0x32 => {
      let resolution : Resolution = {
        x: json_get_int(value, "x"),
        y: json_get_int(value, "y"),
        units: json_get_int(value, "units"),
      }
      let result = IppValue::ResolutionValue(resolution)
      let _ = encode_scalar(result)
      result
    }
    0x33 => {
      let lower = json_get_int(value, "lower")
      let upper = json_get_int(value, "upper")
      if lower > upper {
        raise Invalid("reversed range")
      }
      Range(lower, upper)
    }
    0x34 => {
      if depth >= budget.limits.max_collection_depth {
        raise Limit("JSON collection nesting")
      }
      let members : Array[Attribute] = []
      for field in json_as_array(value) {
        members.push(attribute_from_json(field, budget, depth + 1))
      }
      Collection(members)
    }
    0x35 =>
      TextWithLanguage(
        json_get_string(value, "language"),
        json_get_string(value, "text"),
      )
    0x36 =>
      NameWithLanguage(
        json_get_string(value, "language"),
        json_get_string(value, "text"),
      )
    0x41 => Text(json_as_string(value))
    0x42 => Name(json_as_string(value))
    0x44 => Keyword(json_as_string(value))
    0x45 => Uri(json_as_string(value))
    0x46 => UriScheme(json_as_string(value))
    0x47 => Charset(json_as_string(value))
    0x48 => Language(json_as_string(value))
    0x49 => MimeType(json_as_string(value))
    0x10 | 0x12 | 0x13 | 0x15 | 0x16 | 0x17 => {
      if value != Json::null() {
        raise Invalid("out-of-band JSON value must be null")
      }
      OutOfBand(tag)
    }
    _ => {
      let result = IppValue::Unknown(tag, bytes_from_hex(json_as_string(value)))
      let _ = encode_scalar(result)
      if tag < 0x10 || tag > 0x7f || tag == 0x37 || tag == 0x4a {
        raise Invalid("unsupported JSON value tag")
      }
      result
    }
  }
}

///|
fn attribute_from_json(
  json : Json,
  budget : DecodeBudget,
  depth : Int,
) -> Attribute raise IppError {
  budget.attribute()
  let name = json_get_string(json, "name")
  if !valid_attribute_name(name) {
    raise Invalid("invalid JSON attribute name")
  }
  let values : Array[IppValue] = []
  for item in json_as_array(json_field(json, "values")) {
    values.push(value_from_json(item, budget, depth))
  }
  if values.is_empty() ||
    values.any(fn(value) { value.tag() != values[0].tag() }) {
    raise Invalid("JSON attribute requires nonempty homogeneous values")
  }
  { name, values, }
}

///|
pub fn message_from_json(
  json : Json,
  limits? : DecodeLimits = DecodeLimits::defaults(),
) -> Message raise IppError {
  limits.validate()
  let budget : DecodeBudget = { limits, attributes: 0, values: 0, }
  let version = json_field(json, "version")
  let version = Version::new(
    json_get_int(version, "major"),
    json_get_int(version, "minor"),
  )
  let groups : Array[Group] = []
  for json_group in json_as_array(json_field(json, "groups")) {
    let tag = json_get_int(json_group, "tag")
    if !valid_group_tag(tag) {
      raise Invalid("invalid JSON group tag")
    }
    let attributes : Array[Attribute] = []
    for item in json_as_array(json_field(json_group, "attributes")) {
      attributes.push(attribute_from_json(item, budget, 0))
    }
    groups.push({ tag, attributes, })
  }
  let document_hex = json_get_string(json, "document_hex")
  if document_hex.length() / 2 > limits.max_document_bytes {
    raise Limit("JSON document bytes")
  }
  let message : Message = {
    version,
    code: json_get_int(json, "code"),
    request_id: json_get_int(json, "request_id"),
    groups,
    document: bytes_from_hex(document_hex),
  }
  let _ = encode(message, limits~)
  message
}

///|
pub fn Job::to_json(self : Job) -> Json {
  let state = match self.state {
    Some(state) => Json::string(state.name())
    None => Json::null()
  }
  let uri = match self.uri {
    Some(uri) => Json::string(uri)
    None => Json::null()
  }
  let name = match self.name {
    Some(name) => Json::string(name)
    None => Json::null()
  }
  let message = match self.message {
    Some(message) => Json::string(message)
    None => Json::null()
  }
  let impressions = match self.impressions_completed {
    Some(count) => json_int(count)
    None => Json::null()
  }
  {
    "id": json_int(self.id),
    "uri": uri,
    "name": name,
    "state": state,
    "reasons": Json::array(
      self.reasons.map(fn(reason) { Json::string(reason) }),
    ),
    "message": message,
    "impressions_completed": impressions,
  }
}

///|
pub fn Diagnostic::to_json(self : Diagnostic) -> Json {
  {
    "severity": Json::string(
      if self.severity == Error {
        "error"
      } else {
        "warning"
      },
    ),
    "attribute": Json::string(self.attribute),
    "message": Json::string(self.message),
  }
}
