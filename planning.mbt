///|
/// A plan is a preview, not permission to retry a network submission.
pub(all) struct PrintPlan {
  printer : String
  options : JobOptions
  document_bytes : Int
  diagnostics : Array[Diagnostic]
} derive(Debug)

///|
pub extend PrintPlan with @debug.Debug::{to_repr}

///|
pub fn PrintPlan::can_submit(self : PrintPlan) -> Bool {
  self.document_bytes > 0 &&
  !self.diagnostics.any(fn(item) { item.severity == Error })
}

///|
pub fn Capabilities::plan(
  self : Capabilities,
  options : JobOptions,
  document_bytes : Int,
) -> PrintPlan raise IppError {
  if document_bytes < 0 {
    raise Invalid("document byte count cannot be negative")
  }
  let diagnostics = self.validate_options(options, document_bytes~)
  if document_bytes == 0 {
    diagnostics.push({
      severity: Error,
      attribute: "document",
      message: "empty document cannot be submitted",
    })
  }
  if self.supports_operation(PrintJob) == Some(false) {
    diagnostics.push({
      severity: Error,
      attribute: "operations-supported",
      message: "printer does not support Print-Job",
    })
  }
  let health = self.health()
  for diagnostic in health.diagnostics {
    diagnostics.push(diagnostic)
  }
  { printer: self.name(), options, document_bytes, diagnostics, }
}

///|
/// Select only an explicitly advertised input format. No conversion is implied.
pub fn Capabilities::choose_format(
  self : Capabilities,
  candidates : Array[String],
) -> String raise IppError {
  let supported = self.document_formats()
  for format in candidates {
    if !valid_mime_type(format) {
      raise Invalid("invalid candidate MIME type")
    }
    if supported.contains(format) {
      return format
    }
  }
  raise Unsupported("none of the supplied document formats is advertised")
}

///|
pub fn Capabilities::default_options(
  self : Capabilities,
  name : String,
  format : String,
) -> JobOptions raise IppError {
  let base = JobOptions::new(name, format)
  let copies = match self.printer.get_int("copies-default") {
    Some(n) if n > 0 => n
    _ => 1
  }
  let sides = match self.printer.get_string("sides-default") {
    Some("one-sided") => Some(OneSided)
    Some("two-sided-long-edge") => Some(TwoSidedLongEdge)
    Some("two-sided-short-edge") => Some(TwoSidedShortEdge)
    _ => None
  }
  let resolution = match self.printer.find("printer-resolution-default") {
    Some(attribute) =>
      match attribute.first() {
        Some(ResolutionValue(value)) => Some(value)
        _ => None
      }
    None => None
  }
  let options = JobOptions::{
    ..base,
    copies,
    sides,
    resolution,
    media: self.printer.get_string("media-default"),
    color_mode: self.printer.get_string("print-color-mode-default"),
    print_quality: self.printer.get_int("print-quality-default"),
    orientation: self.printer.get_int("orientation-requested-default"),
    number_up: self.printer.get_int("number-up-default"),
  }
  options.validate()
  self.require_options(options)
  options
}

///|
pub fn JobOptions::to_json(self : JobOptions) -> Json {
  {
    "name": Json::string(self.name),
    "document_format": Json::string(self.document_format),
    "copies": json_int(self.copies),
    "media": match self.media {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "sides": match self.sides {
      Some(value) => Json::string(value.keyword())
      None => Json::null()
    },
    "color_mode": match self.color_mode {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "resolution": match self.resolution {
      Some(value) =>
        {
          "x": json_int(value.x),
          "y": json_int(value.y),
          "units": json_int(value.units),
        }
      None => Json::null()
    },
    "print_quality": match self.print_quality {
      Some(value) => json_int(value)
      None => Json::null()
    },
    "orientation": match self.orientation {
      Some(value) => json_int(value)
      None => Json::null()
    },
    "number_up": match self.number_up {
      Some(value) => json_int(value)
      None => Json::null()
    },
    "page_ranges": Json::array(
      self.page_ranges.map(range => {
        let value : Json = {
          "first": json_int(range.first),
          "last": json_int(range.last),
        }
        value
      }),
    ),
  }
}

///|
pub fn PrintPlan::to_json(self : PrintPlan) -> Json {
  {
    "printer": Json::string(self.printer),
    "options": self.options.to_json(),
    "document_bytes": json_int(self.document_bytes),
    "can_submit": Json::boolean(self.can_submit()),
    "diagnostics": Json::array(self.diagnostics.map(item => item.to_json())),
  }
}

///|
pub fn Capabilities::summary_json(self : Capabilities) -> Json {
  {
    "health": self.health().to_json(),
    "document_formats": Json::array(
      self.document_formats().map(value => Json::string(value)),
    ),
    "media": Json::array(self.media().map(value => Json::string(value))),
    "sides": Json::array(
      self.strings("sides-supported").map(value => Json::string(value)),
    ),
    "color_modes": Json::array(
      self
      .strings("print-color-mode-supported")
      .map(value => Json::string(value)),
    ),
    "resolutions": Json::array(
      self
      .resolutions()
      .map(value => {
        let resolution : Json = {
          "x": json_int(value.x),
          "y": json_int(value.y),
          "units": json_int(value.units),
        }
        resolution
      }),
    ),
    "operations": Json::array(
      self
      .integers("operations-supported")
      .map(code => {
        let operation : Json = {
          "code": json_int(code),
          "name": match operation_from_code(code) {
            Some(value) => Json::string(value.name())
            None => Json::string("unknown")
          },
        }
        operation
      }),
    ),
  }
}
