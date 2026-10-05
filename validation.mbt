///|
pub fn validate_request(request : Message) -> Unit raise IppError {
  if operation_from_code(request.code) is None {
    raise Unsupported("request operation")
  }
  if request.groups.is_empty() || request.groups[0].tag != 1 {
    raise Invalid("operation attributes must be the first group")
  }
  let operation = request.groups[0]
  validate_common(operation)
  if operation.attributes.length() < 3 ||
    operation.attributes[2].name != "printer-uri" {
    raise Invalid("printer-uri must be the third operation attribute")
  }
  match required_single_value(operation, "printer-uri") {
    Uri(uri) => {
      let _ = PrinterUri::parse(uri)
    }
    _ => raise Invalid("printer-uri requires one URI value")
  }
  if request.request_id < 1 {
    raise Invalid("nonpositive request-id")
  }
  if request.groups.filter(fn(group) { group.tag == 1 }).length() != 1 {
    raise Invalid("request has repeated operation groups")
  }
  if request.groups.any(fn(group) { group.tag != 1 && group.tag != 2 }) {
    raise Invalid("request has unsupported attribute group")
  }
  if request.groups.filter(fn(group) { group.tag == 2 }).length() > 1 {
    raise Invalid("request has repeated job groups")
  }
  match operation_from_code(request.code) {
    Some(PrintJob) => {
      if request.document.is_empty() {
        raise Invalid("Print-Job requires a document")
      }
      require_document_format(operation)
    }
    Some(SendDocument) => {
      require_job_id(operation)
      require_document_format(operation)
      match required_single_value(operation, "last-document") {
        Boolean(_) => ()
        _ => raise Invalid("Send-Document requires one last-document boolean")
      }
      if request.document.is_empty() {
        raise Invalid("Send-Document requires a document")
      }
    }
    Some(CancelJob) | Some(GetJobAttributes) => {
      require_job_id(operation)
      require_no_document(request)
    }
    Some(ValidateJob) => {
      require_document_format(operation)
      require_no_document(request)
    }
    _ => require_no_document(request)
  }
}

///|
fn require_job_id(group : Group) -> Unit raise IppError {
  if group.attributes.length() < 4 || group.attributes[3].name != "job-id" {
    raise Invalid("job-id must be the fourth operation attribute")
  }
  match required_single_value(group, "job-id") {
    Integer(value) if value > 0 => ()
    _ => raise Invalid("operation requires one positive integer job-id")
  }
}

///|
fn require_document_format(group : Group) -> Unit raise IppError {
  match required_single_value(group, "document-format") {
    MimeType(format) if valid_mime_type(format) => ()
    _ => raise Invalid("invalid document-format tag or value")
  }
}

///|
fn required_single_value(
  group : Group,
  name : String,
) -> IppValue raise IppError {
  match group.find(name) {
    Some(attribute) if attribute.values.length() == 1 => attribute.values[0]
    _ => raise Invalid("operation requires exactly one value for \{name}")
  }
}

///|
fn require_no_document(message : Message) -> Unit raise IppError {
  if !message.document.is_empty() {
    raise Invalid("unexpected document data")
  }
}

///|
fn validate_common(group : Group) -> Unit raise IppError {
  if group.attributes.length() < 2 {
    raise Protocol("charset and language attributes missing")
  }
  let charset = group.attributes[0]
  let language = group.attributes[1]
  if charset.name != "attributes-charset" ||
    charset.values != [Charset("utf-8")] {
    raise Protocol("first attribute must be UTF-8 charset")
  }
  if language.name != "attributes-natural-language" ||
    language.values.length() != 1 {
    raise Protocol("second attribute must be natural language")
  }
  match language.values[0] {
    Language(value) if !value.is_empty() && value.length() <= 63 => ()
    _ => raise Protocol("invalid natural-language value")
  }
}

///|
pub fn validate_response(
  request : Message,
  response : Message,
) -> Unit raise IppError {
  if response.request_id != request.request_id {
    raise Protocol("response request-id does not match request")
  }
  if response.groups.is_empty() || response.groups[0].tag != 1 {
    raise Protocol("response must begin with operation attributes")
  }
  validate_common(response.groups[0])
  if response.groups.filter(fn(group) { group.tag == 1 }).length() != 1 {
    raise Protocol("response has repeated operation groups")
  }
  if !response.document.is_empty() {
    raise Protocol("unexpected document in response")
  }
  if response.code > 0x05ff ||
    (response.code > 0x00ff && response.code < 0x0400) {
    raise Protocol("invalid status-code class")
  }
}

///|
pub fn unsupported_attributes(response : Message) -> Array[Attribute] {
  let result : Array[Attribute] = []
  for group in response.groups {
    if group.tag == 5 {
      for attribute in group.attributes {
        result.push(attribute)
      }
    }
  }
  result
}

///|
pub fn response_status_message(response : Message) -> String {
  let label = status_name(response.code)
  match response.find_group(1) {
    Some(group) =>
      match group.get_string("status-message") {
        Some(message) => "\{label}: \{message}"
        None => label
      }
    None => label
  }
}

///|
pub fn require_success(response : Message) -> Unit raise IppError {
  if !response.is_success() {
    raise Protocol(response_status_message(response))
  }
}
