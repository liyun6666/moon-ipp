///|
pub(all) struct Resolution {
  x : Int
  y : Int
  units : Int
} derive(Eq, Debug)

///|
pub fn Resolution::dpi(x : Int, y : Int) -> Resolution raise IppError {
  if x < 1 || y < 1 {
    raise Invalid("resolution must be positive")
  }
  { x, y, units: 3, }
}

///|
pub(all) struct IppDateTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
  decisecond : Int
  utc_direction : Int
  utc_hours : Int
  utc_minutes : Int
} derive(Eq, Debug)

///|
pub fn IppDateTime::validate(self : IppDateTime) -> Unit raise IppError {
  if self.year < 0 || self.year > 65535 {
    raise Invalid("date year out of range")
  }
  if self.month < 1 || self.month > 12 {
    raise Invalid("date month out of range")
  }
  let days = match self.month {
    4 | 6 | 9 | 11 => 30
    2 =>
      if self.year % 400 == 0 || (self.year % 4 == 0 && self.year % 100 != 0) {
        29
      } else {
        28
      }
    _ => 31
  }
  if self.day < 1 || self.day > days {
    raise Invalid("date day out of range")
  }
  if self.hour < 0 || self.hour > 23 || self.minute < 0 || self.minute > 59 {
    raise Invalid("date time out of range")
  }
  if self.second < 0 ||
    self.second > 60 ||
    self.decisecond < 0 ||
    self.decisecond > 9 {
    raise Invalid("date seconds out of range")
  }
  if self.utc_direction != 43 && self.utc_direction != 45 {
    raise Invalid("date UTC direction must be + or -")
  }
  if self.utc_hours < 0 ||
    self.utc_hours > 13 ||
    self.utc_minutes < 0 ||
    self.utc_minutes > 59 {
    raise Invalid("date UTC offset out of range")
  }
}

///|
pub(all) enum IppValue {
  Integer(Int)
  Enumeration(Int)
  Boolean(Bool)
  Range(Int, Int)
  ResolutionValue(Resolution)
  DateTime(IppDateTime)
  Text(String)
  Name(String)
  Keyword(String)
  Uri(String)
  UriScheme(String)
  Charset(String)
  Language(String)
  MimeType(String)
  Octets(Bytes)
  TextWithLanguage(String, String)
  NameWithLanguage(String, String)
  Collection(Array[Attribute])
  OutOfBand(Int)
  Unknown(Int, Bytes)
} derive(Eq, Debug)

///|
pub(all) struct Attribute {
  name : String
  values : Array[IppValue]
} derive(Eq, Debug)

///|
pub fn Attribute::new(name : String, value : IppValue) -> Attribute {
  { name, values: [value], }
}

///|
pub fn Attribute::integers(name : String, values : Array[Int]) -> Attribute {
  { name, values: values.map(fn(n) { IppValue::Integer(n) }), }
}

///|
pub fn Attribute::keywords(name : String, values : Array[String]) -> Attribute {
  { name, values: values.map(fn(s) { IppValue::Keyword(s) }), }
}

///|
pub fn Attribute::first(self : Attribute) -> IppValue? {
  self.values.get(0)
}

///|
pub fn Attribute::string_values(self : Attribute) -> Array[String] {
  self.values.filter_map(fn(value) { value.as_string() })
}

///|
pub fn IppValue::as_string(self : IppValue) -> String? {
  match self {
    Text(s)
    | Name(s)
    | Keyword(s)
    | Uri(s)
    | UriScheme(s)
    | Charset(s)
    | Language(s)
    | MimeType(s) => Some(s)
    TextWithLanguage(_, s) | NameWithLanguage(_, s) => Some(s)
    _ => None
  }
}

///|
pub fn IppValue::as_int(self : IppValue) -> Int? {
  match self {
    Integer(n) | Enumeration(n) => Some(n)
    _ => None
  }
}

///|
pub fn IppValue::as_bool(self : IppValue) -> Bool? {
  match self {
    Boolean(b) => Some(b)
    _ => None
  }
}

///|
pub fn IppValue::tag(self : IppValue) -> Int {
  match self {
    Integer(_) => 0x21
    Boolean(_) => 0x22
    Enumeration(_) => 0x23
    Octets(_) => 0x30
    DateTime(_) => 0x31
    ResolutionValue(_) => 0x32
    Range(_, _) => 0x33
    Collection(_) => 0x34
    TextWithLanguage(_, _) => 0x35
    NameWithLanguage(_, _) => 0x36
    Text(_) => 0x41
    Name(_) => 0x42
    Keyword(_) => 0x44
    Uri(_) => 0x45
    UriScheme(_) => 0x46
    Charset(_) => 0x47
    Language(_) => 0x48
    MimeType(_) => 0x49
    OutOfBand(tag) | Unknown(tag, _) => tag
  }
}

///|
pub(all) struct Group {
  tag : Int
  attributes : Array[Attribute]
} derive(Eq, Debug)

///|
pub fn Group::operation(attributes : Array[Attribute]) -> Group {
  { tag: 0x01, attributes, }
}

///|
pub fn Group::job(attributes : Array[Attribute]) -> Group {
  { tag: 0x02, attributes, }
}

///|
pub fn Group::printer(attributes : Array[Attribute]) -> Group {
  { tag: 0x04, attributes, }
}

///|
pub fn Group::find(self : Group, name : String) -> Attribute? {
  for attribute in self.attributes {
    if attribute.name == name {
      return Some(attribute)
    }
  }
  None
}

///|
pub fn Group::get_string(self : Group, name : String) -> String? {
  match self.find(name) {
    Some(attribute) =>
      match attribute.first() {
        Some(value) => value.as_string()
        None => None
      }
    None => None
  }
}

///|
pub fn Group::get_int(self : Group, name : String) -> Int? {
  match self.find(name) {
    Some(attribute) =>
      match attribute.first() {
        Some(value) => value.as_int()
        None => None
      }
    None => None
  }
}

///|
pub fn Group::get_bool(self : Group, name : String) -> Bool? {
  match self.find(name) {
    Some(attribute) =>
      match attribute.first() {
        Some(value) => value.as_bool()
        None => None
      }
    None => None
  }
}

///|
pub(all) struct Message {
  version : Version
  code : Int
  request_id : Int
  groups : Array[Group]
  document : Bytes
} derive(Eq, Debug)

///|
pub fn Message::new(
  code : Int,
  request_id : Int,
  groups : Array[Group],
) -> Message {
  { version: Version::v20(), code, request_id, groups, document: b"", }
}

///|
pub fn Message::find_group(self : Message, tag : Int) -> Group? {
  for group in self.groups {
    if group.tag == tag {
      return Some(group)
    }
  }
  None
}

///|
pub fn Message::find(self : Message, tag : Int, name : String) -> Attribute? {
  match self.find_group(tag) {
    Some(group) => group.find(name)
    None => None
  }
}

///|
pub fn Message::with_document(self : Message, document : Bytes) -> Message {
  { ..self, document, }
}

///|
pub fn Message::is_success(self : Message) -> Bool {
  self.code >= 0 && self.code <= 0x00ff
}
