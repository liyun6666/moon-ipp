///|
pub(all) enum Severity {
  Warning
  Error
} derive(Eq, Debug)

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub(all) struct Diagnostic {
  severity : Severity
  attribute : String
  message : String
} derive(Eq, Debug)

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub(all) struct Capabilities {
  printer : Group
} derive(Eq, Debug)

///|
pub extend Capabilities with Eq::{equal, not_equal}

///|
pub extend Capabilities with @debug.Debug::{to_repr}

///|
pub fn Capabilities::from_response(
  response : Message,
) -> Capabilities raise IppError {
  if !response.is_success() {
    raise Protocol(status_name(response.code))
  }
  let printer = match response.find_group(4) {
    Some(group) => group
    None => raise Protocol("response has no printer attributes")
  }
  { printer, }
}

///|
pub fn Capabilities::strings(
  self : Capabilities,
  name : String,
) -> Array[String] {
  match self.printer.find(name) {
    Some(attribute) => attribute.string_values()
    None => []
  }
}

///|
pub fn Capabilities::integers(self : Capabilities, name : String) -> Array[Int] {
  match self.printer.find(name) {
    Some(attribute) => attribute.values.filter_map(fn(value) { value.as_int() })
    None => []
  }
}

///|
pub fn Capabilities::name(self : Capabilities) -> String {
  match self.printer.get_string("printer-name") {
    Some(name) => name
    None => "unnamed printer"
  }
}

///|
pub fn Capabilities::accepting_jobs(self : Capabilities) -> Bool? {
  self.printer.get_bool("printer-is-accepting-jobs")
}

///|
pub fn Capabilities::supports_operation(
  self : Capabilities,
  operation : Operation,
) -> Bool? {
  match self.printer.find("operations-supported") {
    Some(_) =>
      Some(self.integers("operations-supported").contains(operation.code()))
    None => None
  }
}

///|
pub fn Capabilities::document_formats(self : Capabilities) -> Array[String] {
  self.strings("document-format-supported")
}

///|
pub fn Capabilities::media(self : Capabilities) -> Array[String] {
  self.strings("media-supported")
}

///|
pub fn Capabilities::resolutions(self : Capabilities) -> Array[Resolution] {
  match self.printer.find("printer-resolution-supported") {
    Some(attribute) =>
      attribute.values.filter_map(fn(value) {
        match value {
          ResolutionValue(resolution) => Some(resolution)
          _ => None
        }
      })
    None => []
  }
}

///|
fn diagnostic(
  severity : Severity,
  attribute : String,
  message : String,
) -> Diagnostic {
  { severity, attribute, message, }
}

///|
fn Capabilities::check_string(
  self : Capabilities,
  diagnostics : Array[Diagnostic],
  supported_name : String,
  request_name : String,
  requested : String,
) -> Unit {
  match self.printer.find(supported_name) {
    None =>
      diagnostics.push(
        diagnostic(
          Warning,
          request_name,
          "printer did not advertise supported values",
        ),
      )
    Some(_) =>
      if !self.strings(supported_name).contains(requested) {
        diagnostics.push(
          diagnostic(Error, request_name, "unsupported value: \{requested}"),
        )
      }
  }
}

///|
fn Capabilities::check_integer(
  self : Capabilities,
  diagnostics : Array[Diagnostic],
  supported_name : String,
  request_name : String,
  requested : Int,
) -> Unit {
  match self.printer.find(supported_name) {
    None =>
      diagnostics.push(
        diagnostic(
          Warning,
          request_name,
          "printer did not advertise supported values",
        ),
      )
    Some(attribute) => {
      let supported = attribute.values.any(fn(value) {
        match value {
          Integer(n) | Enumeration(n) => n == requested
          Range(lower, upper) => requested >= lower && requested <= upper
          _ => false
        }
      })
      if !supported {
        diagnostics.push(
          diagnostic(Error, request_name, "unsupported value: \{requested}"),
        )
      }
    }
  }
}

///|
pub fn Capabilities::validate_options(
  self : Capabilities,
  options : JobOptions,
  document_bytes? : Int = 0,
) -> Array[Diagnostic] raise IppError {
  options.validate()
  if document_bytes < 0 {
    raise Invalid("negative document byte count")
  }
  let diagnostics : Array[Diagnostic] = []
  if self.accepting_jobs() == Some(false) {
    diagnostics.push(
      diagnostic(
        Error,
        "printer-is-accepting-jobs",
        "printer is not accepting jobs",
      ),
    )
  }
  if self.supports_operation(PrintJob) == Some(false) {
    diagnostics.push(
      diagnostic(Error, "operations-supported", "Print-Job is not supported"),
    )
  }
  self.check_string(
    diagnostics,
    "document-format-supported",
    "document-format",
    options.document_format,
  )
  self.check_integer(diagnostics, "copies-supported", "copies", options.copies)
  match options.media {
    Some(media) =>
      self.check_string(diagnostics, "media-supported", "media", media)
    None => ()
  }
  match options.sides {
    Some(sides) =>
      self.check_string(
        diagnostics,
        "sides-supported",
        "sides",
        sides.keyword(),
      )
    None => ()
  }
  match options.color_mode {
    Some(mode) =>
      self.check_string(
        diagnostics, "print-color-mode-supported", "print-color-mode", mode,
      )
    None => ()
  }
  match options.print_quality {
    Some(quality) =>
      self.check_integer(
        diagnostics, "print-quality-supported", "print-quality", quality,
      )
    None => ()
  }
  match options.orientation {
    Some(orientation) =>
      self.check_integer(
        diagnostics, "orientation-requested-supported", "orientation-requested",
        orientation,
      )
    None => ()
  }
  match options.number_up {
    Some(count) =>
      self.check_integer(diagnostics, "number-up-supported", "number-up", count)
    None => ()
  }
  match options.resolution {
    Some(resolution) =>
      match self.printer.find("printer-resolution-supported") {
        None =>
          diagnostics.push(
            diagnostic(
              Warning,
              "printer-resolution",
              "printer did not advertise supported resolutions",
            ),
          )
        Some(_) =>
          if !self.resolutions().contains(resolution) {
            diagnostics.push(
              diagnostic(Error, "printer-resolution", "unsupported resolution"),
            )
          }
      }
    None => ()
  }
  if !options.page_ranges.is_empty() &&
    self.printer.get_bool("page-ranges-supported") != Some(true) {
    diagnostics.push(
      diagnostic(
        Error,
        "page-ranges",
        "printer did not advertise page range support",
      ),
    )
  }
  if document_bytes > 0 &&
    self.printer.find("job-k-octets-supported") is Some(_) {
    let kibibytes = document_bytes / 1024 +
      (if document_bytes % 1024 != 0 { 1 } else { 0 })
    self.check_integer(
      diagnostics, "job-k-octets-supported", "job-k-octets", kibibytes,
    )
  }
  diagnostics
}

///|
pub fn diagnostics_have_errors(diagnostics : Array[Diagnostic]) -> Bool {
  diagnostics.any(fn(item) { item.severity == Error })
}

///|
pub fn Capabilities::require_options(
  self : Capabilities,
  options : JobOptions,
  document_bytes? : Int = 0,
) -> Unit raise IppError {
  let errors = self
    .validate_options(options, document_bytes~)
    .filter(fn(item) { item.severity == Error })
  if !errors.is_empty() {
    let details = errors
      .map(fn(item) { "\{item.attribute}: \{item.message}" })
      .join("; ")
    raise Unsupported(details)
  }
}
