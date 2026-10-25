///|
pub(all) struct MediaSize {
  x : Int
  y : Int
} derive(Eq, Debug)

///|
pub extend MediaSize with Eq::{equal, not_equal}

///|
pub extend MediaSize with @debug.Debug::{to_repr}

///|
/// Dimensions are expressed in hundredths of a millimetre, as specified by PWG.
pub fn MediaSize::new(x : Int, y : Int) -> MediaSize raise IppError {
  if x < 1 || y < 1 {
    raise Invalid("media dimensions must be positive")
  }
  { x, y, }
}

///|
pub fn MediaSize::a4() -> MediaSize {
  { x: 21000, y: 29700, }
}

///|
pub fn MediaSize::letter() -> MediaSize {
  { x: 21590, y: 27940, }
}

///|
pub fn MediaSize::collection(self : MediaSize) -> IppValue {
  Collection([
    Attribute::new("x-dimension", Integer(self.x)),
    Attribute::new("y-dimension", Integer(self.y)),
  ])
}

///|
pub(all) struct MediaMargins {
  top : Int
  bottom : Int
  left : Int
  right : Int
} derive(Eq, Debug)

///|
pub extend MediaMargins with Eq::{equal, not_equal}

///|
pub extend MediaMargins with @debug.Debug::{to_repr}

///|
pub fn MediaMargins::new(
  top : Int,
  bottom : Int,
  left : Int,
  right : Int,
) -> MediaMargins raise IppError {
  if top < 0 || bottom < 0 || left < 0 || right < 0 {
    raise Invalid("media margins cannot be negative")
  }
  { top, bottom, left, right, }
}

///|
pub(all) struct MediaSpec {
  size : MediaSize
  margins : MediaMargins?
  source : String?
  kind : String?
  name : String?
} derive(Eq, Debug)

///|
pub extend MediaSpec with Eq::{equal, not_equal}

///|
pub extend MediaSpec with @debug.Debug::{to_repr}

///|
pub fn MediaSpec::new(size : MediaSize) -> MediaSpec {
  { size, margins: None, source: None, kind: None, name: None, }
}

///|
pub fn MediaSpec::validate(self : MediaSpec) -> Unit raise IppError {
  let _ = MediaSize::new(self.size.x, self.size.y)
  match self.margins {
    Some(margins) => {
      let _ = MediaMargins::new(
        margins.top,
        margins.bottom,
        margins.left,
        margins.right,
      )
      if margins.left >= self.size.x ||
        margins.right >= self.size.x - margins.left ||
        margins.top >= self.size.y ||
        margins.bottom >= self.size.y - margins.top {
        raise Invalid("media margins leave no printable area")
      }
    }
    None => ()
  }
  for keyword in [self.source, self.kind] {
    match keyword {
      Some(value) =>
        if !valid_attribute_name(value) {
          raise Invalid("invalid media collection keyword")
        }
      None => ()
    }
  }
  match self.name {
    Some(name) => validate_string_value(0x42, name)
    None => ()
  }
}

///|
pub fn MediaSpec::collection(self : MediaSpec) -> IppValue raise IppError {
  self.validate()
  let fields = [Attribute::new("media-size", self.size.collection())]
  match self.margins {
    Some(margins) => {
      fields.push(Attribute::new("media-top-margin", Integer(margins.top)))
      fields.push(
        Attribute::new("media-bottom-margin", Integer(margins.bottom)),
      )
      fields.push(Attribute::new("media-left-margin", Integer(margins.left)))
      fields.push(Attribute::new("media-right-margin", Integer(margins.right)))
    }
    None => ()
  }
  match self.source {
    Some(value) => fields.push(Attribute::new("media-source", Keyword(value)))
    None => ()
  }
  match self.kind {
    Some(value) => fields.push(Attribute::new("media-type", Keyword(value)))
    None => ()
  }
  match self.name {
    Some(value) =>
      fields.push(
        Attribute::new(
          "media-size-name",
          if valid_attribute_name(value) {
            Keyword(value)
          } else {
            Name(value)
          },
        ),
      )
    None => ()
  }
  Collection(fields)
}

///|
fn collection_fields(value : IppValue) -> Group raise IppError {
  match value {
    Collection(fields) => {
      validate_attribute_set(fields) catch {
        _ => raise Invalid("invalid or duplicate media collection field")
      }
      Group::printer(fields)
    }
    _ => raise Invalid("media collection expected")
  }
}

///|
fn required_collection_value(
  group : Group,
  name : String,
) -> IppValue raise IppError {
  match group.find(name) {
    Some(attribute) =>
      match attribute.values {
        [value] => value
        _ => raise Invalid("media collection field must have exactly one value")
      }
    None => raise Invalid("missing media collection field: \{name}")
  }
}

///|
fn optional_collection_keyword(
  group : Group,
  name : String,
) -> String? raise IppError {
  match group.find(name) {
    None => None
    Some(_) =>
      match required_collection_value(group, name) {
        Keyword(value) => Some(value)
        _ => raise Invalid("media collection field requires a keyword")
      }
  }
}

///|
fn required_collection_int(group : Group, name : String) -> Int raise IppError {
  match required_collection_value(group, name) {
    Integer(value) => value
    _ => raise Invalid("media dimension or margin requires integer")
  }
}

///|
pub fn media_spec_from_collection(value : IppValue) -> MediaSpec raise IppError {
  let fields = collection_fields(value)
  let size_fields = collection_fields(
    required_collection_value(fields, "media-size"),
  )
  let size = MediaSize::new(
    required_collection_int(size_fields, "x-dimension"),
    required_collection_int(size_fields, "y-dimension"),
  )
  let margin_names = [
    "media-top-margin", "media-bottom-margin", "media-left-margin", "media-right-margin",
  ]
  let present = margin_names
    .filter(fn(name) { fields.find(name) is Some(_) })
    .length()
  let margins = if present == 0 {
    None
  } else {
    if present != 4 {
      raise Invalid("media margins must specify all four edges")
    }
    Some(
      MediaMargins::new(
        required_collection_int(fields, margin_names[0]),
        required_collection_int(fields, margin_names[1]),
        required_collection_int(fields, margin_names[2]),
        required_collection_int(fields, margin_names[3]),
      ),
    )
  }
  let spec = MediaSpec::{
    size,
    margins,
    source: optional_collection_keyword(fields, "media-source"),
    kind: optional_collection_keyword(fields, "media-type"),
    name: match fields.find("media-size-name") {
      None => None
      Some(_) =>
        match required_collection_value(fields, "media-size-name") {
          Keyword(value) | Name(value) | NameWithLanguage(_, value) =>
            Some(value)
          _ => raise Invalid("media-size-name requires a name or keyword")
        }
    },
  }
  spec.validate()
  spec
}

///|
pub fn Capabilities::media_database(
  self : Capabilities,
) -> Array[MediaSpec] raise IppError {
  match self.printer.find("media-col-database") {
    None => []
    Some(attribute) =>
      attribute.values.map(value => media_spec_from_collection(value))
  }
}

///|
pub fn Capabilities::validate_media(
  self : Capabilities,
  spec : MediaSpec,
) -> Array[Diagnostic] raise IppError {
  spec.validate()
  let diagnostics : Array[Diagnostic] = []
  let database = self.media_database()
  if database.is_empty() {
    diagnostics.push({
      severity: Warning,
      attribute: "media-col",
      message: "printer has not advertised its media database",
    })
    return diagnostics
  }
  let matching = database.filter(fn(candidate) { candidate.size == spec.size })
  if matching.is_empty() {
    diagnostics.push({
      severity: Error,
      attribute: "media-size",
      message: "requested dimensions are not in media-col-database",
    })
  } else {
    let compatible = matching.any(fn(candidate) {
      (spec.source is None || candidate.source == spec.source) &&
      (spec.kind is None || candidate.kind == spec.kind) &&
      (spec.margins is None || candidate.margins == spec.margins)
    })
    if !compatible {
      diagnostics.push({
        severity: Error,
        attribute: "media-col",
        message: "requested tray, media type or margins do not match a media entry",
      })
    }
  }
  diagnostics
}

///|
/// Add media-col without losing the operation attributes or document bytes.
pub fn with_media_collection(
  message : Message,
  spec : MediaSpec,
) -> Message raise IppError {
  if message.code != 2 && message.code != 4 && message.code != 5 {
    raise Invalid(
      "media-col is only supported for print, validate or create-job",
    )
  }
  let value = spec.collection()
  let groups = message.groups.map(fn(group) {
    if group.tag != 2 {
      return group
    }
    let attributes = group.attributes.filter(fn(attribute) {
      attribute.name != "media" && attribute.name != "media-col"
    })
    attributes.push(Attribute::new("media-col", value))
    Group::job(attributes)
  })
  if !groups.any(fn(group) { group.tag == 2 }) {
    groups.push(Group::job([Attribute::new("media-col", value)]))
  }
  Message::{ ..message, groups, }
}
