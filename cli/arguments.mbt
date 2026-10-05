///|
pub(all) enum Command {
  Help
  Version
  Capabilities
  Health
  Jobs
  Job
  Cancel
  Print
  Validate
  Create
  Send
  Wait
  Decode
  Encode
  Compare
} derive(Eq, @debug.Debug)

///|
pub extend Command with Eq::{equal, not_equal}

///|
pub extend Command with @debug.Debug::{to_repr}

///|
pub(all) struct Arguments {
  command : Command
  uri : String?
  input : String?
  output : String?
  other : String?
  user : String
  options : @ipp.JobOptions
  job_id : Int?
  timeout_ms : Int
  interval_ms : Int
  polls : Int
  which : String
  mine : Bool
  limit : Int
  requested : Array[String]
  last_document : Bool
  preflight : Bool
} derive(@debug.Debug)

///|
pub extend Arguments with @debug.Debug::{to_repr}

///|
fn command_from_string(text : String) -> Command raise @ipp.IppError {
  match text {
    "help" | "--help" | "-h" => Help
    "version" | "--version" => Version
    "capabilities" => Capabilities
    "health" => Health
    "jobs" => Jobs
    "job" => Job
    "cancel" => Cancel
    "print" => Print
    "validate" => Validate
    "create" => Create
    "send" => Send
    "wait" => Wait
    "decode" => Decode
    "encode" => Encode
    "compare" => Compare
    _ => raise @ipp.Invalid("unknown command: \{text}")
  }
}

///|
fn decimal(text : String, maximum : Int) -> Int raise @ipp.IppError {
  if text.is_empty() {
    raise @ipp.Invalid("empty numeric option")
  }
  let mut result = 0
  for character in text.to_array() {
    let digit = character.to_int() - 48
    if digit < 0 || digit > 9 || result > (maximum - digit) / 10 {
      raise @ipp.Invalid("invalid numeric option: \{text}")
    }
    result = result * 10 + digit
  }
  result
}

///|
fn positive(text : String, maximum : Int) -> Int raise @ipp.IppError {
  let result = decimal(text, maximum)
  if result == 0 {
    raise @ipp.Invalid("numeric option must be positive")
  }
  result
}

///|
fn resolution(text : String) -> @ipp.Resolution raise @ipp.IppError {
  match text.split_once("x") {
    Some((x, y)) =>
      @ipp.Resolution::dpi(
        positive(x.to_owned(), 100000),
        positive(y.to_owned(), 100000),
      )
    None => {
      let value = positive(text, 100000)
      @ipp.Resolution::dpi(value, value)
    }
  }
}

///|
fn option_names() -> Array[String] {
  [
    "uri", "input", "output", "other", "user", "format", "name", "copies", "media",
    "sides", "color", "resolution", "quality", "orientation", "number-up", "pages",
    "job-id", "timeout", "interval", "polls", "which", "limit", "requested", "mine",
    "no-preflight", "more-documents",
  ]
}

///|
fn boolean_option(name : String) -> Bool {
  name == "mine" || name == "no-preflight" || name == "more-documents"
}

///|
fn optional(values : Map[String, String], name : String) -> String? {
  values.get(name)
}

///|
fn default_value(
  values : Map[String, String],
  name : String,
  fallback : String,
) -> String {
  match values.get(name) {
    Some(value) => value
    None => fallback
  }
}

///|
fn required(
  values : Map[String, String],
  name : String,
) -> String raise @ipp.IppError {
  match values.get(name) {
    Some(value) if !value.is_empty() => value
    _ => raise @ipp.Invalid("missing --\{name}")
  }
}

///|
fn require_allowed(
  command : Command,
  name : String,
) -> Unit raise @ipp.IppError {
  let allowed = match name {
    "uri" | "user" | "timeout" =>
      command != Decode && command != Encode && command != Compare
    "input" =>
      command == Print ||
      command == Send ||
      command == Decode ||
      command == Encode ||
      command == Compare
    "output" => command == Decode || command == Encode
    "other" => command == Compare
    "job-id" =>
      command == Job || command == Cancel || command == Send || command == Wait
    "interval" | "polls" => command == Wait
    "which" | "mine" | "limit" => command == Jobs
    "requested" => command == Capabilities
    "more-documents" => command == Send
    "no-preflight" => command == Print
    "format" =>
      command == Print ||
      command == Validate ||
      command == Create ||
      command == Send
    _ => command == Print || command == Validate || command == Create
  }
  if !allowed {
    raise @ipp.Invalid("option --\{name} does not apply to this command")
  }
}

///| Parse arguments excluding the executable name. Duplicate and inapplicable

///|
/// options are errors, so a mistyped print option cannot be silently ignored.
pub fn parse(arguments : Array[String]) -> Arguments raise @ipp.IppError {
  let command = if arguments.is_empty() {
    Help
  } else {
    command_from_string(arguments[0])
  }
  let values : Map[String, String] = Map([])
  let mut index = 1
  while index < arguments.length() {
    let token = arguments[index]
    if !token.has_prefix("--") {
      raise @ipp.Invalid("options must start with --: \{token}")
    }
    let without_prefix = token.exact_view(start=2).to_owned()
    let (name, inline_value) = match without_prefix.split_once("=") {
      Some((name, value)) => (name.to_owned(), Some(value.to_owned()))
      None => (without_prefix, None)
    }
    if !option_names().contains(name) {
      raise @ipp.Invalid("unknown option: --\{name}")
    }
    if values.contains(name) {
      raise @ipp.Invalid("duplicate option: --\{name}")
    }
    require_allowed(command, name)
    let value = if boolean_option(name) {
      if inline_value is Some(_) {
        raise @ipp.Invalid("flag does not accept a value: --\{name}")
      }
      "true"
    } else {
      match inline_value {
        Some(value) => value
        None => {
          index += 1
          if index >= arguments.length() || arguments[index].has_prefix("--") {
            raise @ipp.Invalid("missing option value: --\{name}")
          }
          arguments[index]
        }
      }
    }
    if value.is_empty() {
      raise @ipp.Invalid("empty option: --\{name}")
    }
    values[name] = value
    index += 1
  }
  let network = match command {
    Help | Version | Decode | Encode | Compare => false
    _ => true
  }
  let uri = if network {
    let text = required(values, "uri")
    let _ = @ipp.PrinterUri::parse(text)
    Some(text)
  } else {
    None
  }
  let input = if command == Print ||
    command == Send ||
    command == Decode ||
    command == Encode ||
    command == Compare {
    Some(required(values, "input"))
  } else {
    None
  }
  let format = match optional(values, "format") {
    Some(format) => format
    None =>
      match input {
        Some(path) =>
          match @ipp.infer_document_format(path) {
            Some(value) => value
            None => "application/octet-stream"
          }
        None => "application/octet-stream"
      }
  }
  let options = @ipp.JobOptions::{
    ..@ipp.JobOptions::new(
      default_value(values, "name", "moon-ipp document"),
      format,
    ),
    copies: positive(default_value(values, "copies", "1"), 2147483647),
    media: optional(values, "media"),
    sides: match optional(values, "sides") {
      Some(value) => Some(@ipp.sides_from_string(value))
      None => None
    },
    color_mode: optional(values, "color"),
    resolution: match optional(values, "resolution") {
      Some(value) => Some(resolution(value))
      None => None
    },
    print_quality: match optional(values, "quality") {
      Some(value) => Some(positive(value, 5))
      None => None
    },
    orientation: match optional(values, "orientation") {
      Some(value) => Some(positive(value, 6))
      None => None
    },
    number_up: match optional(values, "number-up") {
      Some(value) => Some(positive(value, 2147483647))
      None => None
    },
    page_ranges: match optional(values, "pages") {
      Some(value) => @ipp.parse_page_ranges(value)
      None => []
    },
  }
  options.validate()
  let job_id = if command == Job ||
    command == Cancel ||
    command == Send ||
    command == Wait {
    Some(positive(required(values, "job-id"), 2147483647))
  } else {
    None
  }
  let requested = match optional(values, "requested") {
    Some(text) => {
      let names = text.split(",").map(view => view.to_owned()).to_array()
      if names.any(fn(name) { !@ipp.valid_attribute_name(name) }) {
        raise @ipp.Invalid("invalid requested attribute")
      }
      names
    }
    None => []
  }
  let which = default_value(values, "which", "not-completed")
  if which != "all" && which != "completed" && which != "not-completed" {
    raise @ipp.Invalid("invalid --which")
  }
  {
    command,
    uri,
    input,
    job_id,
    options,
    requested,
    output: if command == Encode {
      Some(required(values, "output"))
    } else {
      optional(values, "output")
    },
    other: if command == Compare {
      Some(required(values, "other"))
    } else {
      None
    },
    user: default_value(values, "user", "anonymous"),
    timeout_ms: positive(default_value(values, "timeout", "10000"), 300000),
    interval_ms: positive(default_value(values, "interval", "1000"), 60000),
    polls: positive(default_value(values, "polls", "60"), 10000),
    which,
    mine: values.contains("mine"),
    limit: positive(default_value(values, "limit", "100"), 10000),
    last_document: !values.contains("more-documents"),
    preflight: !values.contains("no-preflight"),
  }
}

///|
pub fn help() -> String {
  let text =
    #|moon-ipp 0.1.0 — MoonBit IPP library and client
    #|Usage: moon run cmd/main --target native -- <command> [options]
    #|
    #|Commands:
    #|  capabilities  --uri URI [--requested name,name]
    #|  health        --uri URI
    #|  jobs          --uri URI [--which all|completed|not-completed] [--mine] [--limit N]
    #|  job|cancel    --uri URI --job-id N
    #|  print         --uri URI --input FILE [print options] [--no-preflight]
    #|  validate      --uri URI --format MIME [print options]
    #|  create        --uri URI --format MIME [print options]
    #|  send          --uri URI --job-id N --input FILE [--format MIME] [--more-documents]
    #|  wait          --uri URI --job-id N [--interval MS] [--polls N]
    #|  decode        --input IPP_FILE [--output JSON_FILE]
    #|  encode        --input JSON_FILE --output IPP_FILE
    #|  compare       --input BEFORE_JSON --other AFTER_JSON
    #|
    #|Print options: --name TEXT --format MIME --copies N --media KEYWORD
    #|  --sides one-sided|two-sided-long-edge|two-sided-short-edge
    #|  --color auto|color|monochrome|bi-level --resolution DPI or XxY
    #|  --quality 3|4|5 --orientation 3|4|5|6 --number-up N --pages 1-3,5
    #|Network options: --user TEXT --timeout MS
    #|Authentication: MOON_IPP_AUTHORIZATION environment variable, ipps only.
    #|Output: JSON. Print uncertainty is an error; never retry automatically.
  text
}
