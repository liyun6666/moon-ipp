///|
pub suberror IppError {
  Invalid(String)
  Truncated(Int, Int)
  Limit(String)
  Protocol(String)
  Unsupported(String)
} derive(Debug)

///|
pub(all) struct Version {
  major : Int
  minor : Int
} derive(Eq, Debug)

///|
pub fn Version::new(major : Int, minor : Int) -> Version raise IppError {
  if major < 1 || major > 2 || minor < 0 || minor > 2 {
    raise Invalid("unsupported IPP version")
  }
  { major, minor, }
}

///|
pub fn Version::v11() -> Version {
  { major: 1, minor: 1, }
}

///|
pub fn Version::v20() -> Version {
  { major: 2, minor: 0, }
}

///|
pub fn Version::text(self : Version) -> String {
  "\{self.major}.\{self.minor}"
}

///|
pub(all) struct DecodeLimits {
  max_message_bytes : Int
  max_attributes : Int
  max_values : Int
  max_collection_depth : Int
  max_document_bytes : Int
} derive(Eq, Debug)

///|
pub fn DecodeLimits::defaults() -> DecodeLimits {
  {
    max_message_bytes: 1048576,
    max_attributes: 4096,
    max_values: 16384,
    max_collection_depth: 16,
    max_document_bytes: 16777216,
  }
}

///|
pub fn DecodeLimits::validate(self : DecodeLimits) -> Unit raise IppError {
  if self.max_message_bytes < 9 {
    raise Invalid("message limit must be at least 9 bytes")
  }
  if self.max_attributes < 1 || self.max_values < 1 {
    raise Invalid("attribute and value limits must be positive")
  }
  if self.max_collection_depth < 0 || self.max_collection_depth > 64 {
    raise Invalid("collection depth limit must be between 0 and 64")
  }
  if self.max_document_bytes < 0 {
    raise Invalid("document limit must not be negative")
  }
}
