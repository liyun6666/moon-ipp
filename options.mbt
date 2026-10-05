///|
pub(all) enum Sides {
  OneSided
  TwoSidedLongEdge
  TwoSidedShortEdge
} derive(Eq, Debug)

///|
pub extend Sides with Eq::{equal, not_equal}

///|
pub extend Sides with @debug.Debug::{to_repr}

///|
pub fn Sides::keyword(self : Sides) -> String {
  match self {
    OneSided => "one-sided"
    TwoSidedLongEdge => "two-sided-long-edge"
    TwoSidedShortEdge => "two-sided-short-edge"
  }
}

///|
pub fn sides_from_string(text : String) -> Sides raise IppError {
  match text {
    "one-sided" => OneSided
    "two-sided-long-edge" => TwoSidedLongEdge
    "two-sided-short-edge" => TwoSidedShortEdge
    _ => raise Invalid("unknown sides value")
  }
}

///|
pub(all) struct PageRange {
  first : Int
  last : Int
} derive(Eq, Debug)

///|
pub extend PageRange with Eq::{equal, not_equal}

///|
pub extend PageRange with @debug.Debug::{to_repr}

///|
pub fn PageRange::new(first : Int, last : Int) -> PageRange raise IppError {
  if first < 1 || last < first {
    raise Invalid("invalid page range")
  }
  { first, last, }
}

///|
pub(all) struct JobOptions {
  name : String
  document_format : String
  copies : Int
  media : String?
  sides : Sides?
  color_mode : String?
  resolution : Resolution?
  print_quality : Int?
  orientation : Int?
  number_up : Int?
  page_ranges : Array[PageRange]
} derive(Eq, Debug)

///|
pub extend JobOptions with Eq::{equal, not_equal}

///|
pub extend JobOptions with @debug.Debug::{to_repr}

///|
pub fn JobOptions::new(name : String, document_format : String) -> JobOptions {
  {
    name,
    document_format,
    copies: 1,
    media: None,
    sides: None,
    color_mode: None,
    resolution: None,
    print_quality: None,
    orientation: None,
    number_up: None,
    page_ranges: [],
  }
}

///|
pub fn valid_mime_type(text : String) -> Bool {
  if text.length() < 3 || text.length() > 255 {
    return false
  }
  let parts = text.split("/").to_array()
  if parts.length() != 2 || parts[0].is_empty() || parts[1].is_empty() {
    return false
  }
  for char in text.to_array() {
    let n = char.to_int()
    if !((n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 33 ||
      n == 35 ||
      n == 36 ||
      n == 38 ||
      n == 45 ||
      n == 46 ||
      n == 43 ||
      n == 47 ||
      n == 94 ||
      n == 95) {
      return false
    }
  }
  true
}

///|
pub fn JobOptions::validate(self : JobOptions) -> Unit raise IppError {
  let name_length = encode_utf8(self.name).length()
  if name_length < 1 || name_length > 255 {
    raise Invalid("job name must be 1 to 255 UTF-8 bytes")
  }
  if !valid_mime_type(self.document_format) {
    raise Invalid("invalid document MIME type")
  }
  if self.copies < 1 {
    raise Invalid("copies must be positive")
  }
  match self.media {
    Some(media) =>
      if !valid_attribute_name(media) {
        raise Invalid("invalid media keyword")
      }
    None => ()
  }
  match self.color_mode {
    Some(mode) =>
      if mode != "auto" &&
        mode != "color" &&
        mode != "monochrome" &&
        mode != "bi-level" {
        raise Invalid("invalid print color mode")
      }
    None => ()
  }
  match self.resolution {
    Some(resolution) =>
      if resolution.x < 1 ||
        resolution.y < 1 ||
        (resolution.units != 3 && resolution.units != 4) {
        raise Invalid("invalid printer resolution")
      }
    None => ()
  }
  match self.print_quality {
    Some(quality) =>
      if quality < 3 || quality > 5 {
        raise Invalid("print quality must be 3, 4 or 5")
      }
    None => ()
  }
  match self.orientation {
    Some(orientation) =>
      if orientation < 3 || orientation > 6 {
        raise Invalid("orientation must be between 3 and 6")
      }
    None => ()
  }
  match self.number_up {
    Some(count) => if count < 1 { raise Invalid("number-up must be positive") }
    None => ()
  }
  let mut previous = 0
  for range in self.page_ranges {
    if range.first < 1 || range.last < range.first || range.first <= previous {
      raise Invalid("page ranges must be positive, ordered and disjoint")
    }
    previous = range.last
  }
}

///|
pub fn JobOptions::attributes(self : JobOptions) -> Array[Attribute] {
  let attributes = [Attribute::new("copies", Integer(self.copies))]
  match self.media {
    Some(media) => attributes.push(Attribute::new("media", Keyword(media)))
    None => ()
  }
  match self.sides {
    Some(sides) =>
      attributes.push(Attribute::new("sides", Keyword(sides.keyword())))
    None => ()
  }
  match self.color_mode {
    Some(mode) =>
      attributes.push(Attribute::new("print-color-mode", Keyword(mode)))
    None => ()
  }
  match self.resolution {
    Some(resolution) =>
      attributes.push(
        Attribute::new("printer-resolution", ResolutionValue(resolution)),
      )
    None => ()
  }
  match self.print_quality {
    Some(quality) =>
      attributes.push(Attribute::new("print-quality", Enumeration(quality)))
    None => ()
  }
  match self.orientation {
    Some(orientation) =>
      attributes.push(
        Attribute::new("orientation-requested", Enumeration(orientation)),
      )
    None => ()
  }
  match self.number_up {
    Some(count) => attributes.push(Attribute::new("number-up", Integer(count)))
    None => ()
  }
  if !self.page_ranges.is_empty() {
    attributes.push({
      name: "page-ranges",
      values: self.page_ranges.map(fn(range) {
        IppValue::Range(range.first, range.last)
      }),
    })
  }
  attributes
}

///|
pub fn parse_page_ranges(text : String) -> Array[PageRange] raise IppError {
  if text.is_empty() {
    raise Invalid("page range text is empty")
  }
  let ranges : Array[PageRange] = []
  let mut previous = 0
  for part in text.split(",") {
    let value = part.to_owned()
    let range = match value.split_once("-") {
      Some((start, end)) =>
        PageRange::new(
          parse_decimal(start.to_owned(), 2147483647),
          parse_decimal(end.to_owned(), 2147483647),
        )
      None => {
        let page = parse_decimal(value, 2147483647)
        PageRange::new(page, page)
      }
    }
    if range.first <= previous {
      raise Invalid("page ranges overlap or are not sorted")
    }
    previous = range.last
    ranges.push(range)
  }
  ranges
}

///|
pub fn infer_document_format(filename : String) -> String? {
  let lower = filename.to_lower()
  if lower.has_suffix(".pdf") {
    Some("application/pdf")
  } else if lower.has_suffix(".jpg") || lower.has_suffix(".jpeg") {
    Some("image/jpeg")
  } else if lower.has_suffix(".png") {
    Some("image/png")
  } else if lower.has_suffix(".ps") {
    Some("application/postscript")
  } else if lower.has_suffix(".txt") {
    Some("text/plain")
  } else {
    None
  }
}
