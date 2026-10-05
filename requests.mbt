///|
pub(all) struct RequestContext {
  printer : PrinterUri
  user : String
  language : String
  version : Version
} derive(Eq, Debug)

///|
pub extend RequestContext with Eq::{equal, not_equal}

///|
pub extend RequestContext with @debug.Debug::{to_repr}

///|
pub fn RequestContext::new(
  uri : String,
  user? : String = "anonymous",
  language? : String = "en",
) -> RequestContext raise IppError {
  if encode_utf8(user).length() < 1 || encode_utf8(user).length() > 255 {
    raise Invalid("requesting user name length out of range")
  }
  if language.is_empty() || language.length() > 63 {
    raise Invalid("invalid natural language")
  }
  { printer: PrinterUri::parse(uri), user, language, version: Version::v20(), }
}

///|
fn RequestContext::attributes(self : RequestContext) -> Array[Attribute] {
  [
    Attribute::new("attributes-charset", Charset("utf-8")),
    Attribute::new("attributes-natural-language", Language(self.language)),
    Attribute::new("printer-uri", Uri(self.printer.text())),
    Attribute::new("requesting-user-name", Name(self.user)),
  ]
}

///|
fn RequestContext::request(
  self : RequestContext,
  operation : Operation,
  request_id : Int,
  attributes : Array[Attribute],
) -> Message raise IppError {
  if request_id < 1 {
    raise Invalid("request-id must be positive")
  }
  {
    version: self.version,
    code: operation.code(),
    request_id,
    groups: [Group::operation(attributes)],
    document: b"",
  }
}

///|
pub fn RequestContext::printer_attributes(
  self : RequestContext,
  request_id : Int,
  requested? : Array[String] = [],
) -> Message raise IppError {
  let attributes = self.attributes()
  if !requested.is_empty() {
    attributes.push(Attribute::keywords("requested-attributes", requested))
  }
  self.request(GetPrinterAttributes, request_id, attributes)
}

///|
pub fn RequestContext::get_jobs(
  self : RequestContext,
  request_id : Int,
  which? : String = "not-completed",
  mine? : Bool = false,
  limit? : Int = 100,
) -> Message raise IppError {
  if which != "not-completed" && which != "completed" && which != "all" {
    raise Invalid("which-jobs must be all, completed or not-completed")
  }
  if limit < 1 || limit > 10000 {
    raise Invalid("job limit out of range")
  }
  let attributes = self.attributes()
  attributes.push(Attribute::new("which-jobs", Keyword(which)))
  attributes.push(Attribute::new("my-jobs", Boolean(mine)))
  attributes.push(Attribute::new("limit", Integer(limit)))
  attributes.push(
    Attribute::keywords("requested-attributes", [
      "job-id", "job-uri", "job-name", "job-state", "job-state-reasons", "job-state-message",
      "job-impressions-completed",
    ]),
  )
  self.request(GetJobs, request_id, attributes)
}

///|
fn RequestContext::job_request(
  self : RequestContext,
  operation : Operation,
  request_id : Int,
  job_id : Int,
) -> Message raise IppError {
  if job_id < 1 {
    raise Invalid("job-id must be positive")
  }
  let attributes = self.attributes()
  attributes.push(Attribute::new("job-id", Integer(job_id)))
  self.request(operation, request_id, attributes)
}

///|
pub fn RequestContext::job_attributes(
  self : RequestContext,
  request_id : Int,
  job_id : Int,
) -> Message raise IppError {
  self.job_request(GetJobAttributes, request_id, job_id)
}

///|
pub fn RequestContext::cancel_job(
  self : RequestContext,
  request_id : Int,
  job_id : Int,
) -> Message raise IppError {
  self.job_request(CancelJob, request_id, job_id)
}

///|
pub fn RequestContext::validate_job(
  self : RequestContext,
  request_id : Int,
  options : JobOptions,
) -> Message raise IppError {
  options.validate()
  let attributes = self.attributes()
  attributes.push(
    Attribute::new("document-format", MimeType(options.document_format)),
  )
  attributes.push(Attribute::new("job-name", Name(options.name)))
  attributes.push(Attribute::new("ipp-attribute-fidelity", Boolean(true)))
  let request = self.request(ValidateJob, request_id, attributes)
  request.groups.push(Group::job(options.attributes()))
  request
}

///|
pub fn RequestContext::print_job(
  self : RequestContext,
  request_id : Int,
  options : JobOptions,
  document : Bytes,
) -> Message raise IppError {
  if document.is_empty() {
    raise Invalid("print document must not be empty")
  }
  let request = self.validate_job(request_id, options)
  { ..request, code: Operation::PrintJob.code(), document, }
}

///|
pub fn RequestContext::create_job(
  self : RequestContext,
  request_id : Int,
  options : JobOptions,
) -> Message raise IppError {
  options.validate()
  let attributes = self.attributes()
  attributes.push(Attribute::new("job-name", Name(options.name)))
  attributes.push(Attribute::new("ipp-attribute-fidelity", Boolean(true)))
  let request = self.request(CreateJob, request_id, attributes)
  request.groups.push(Group::job(options.attributes()))
  request
}

///|
pub fn RequestContext::send_document(
  self : RequestContext,
  request_id : Int,
  job_id : Int,
  format : String,
  document : Bytes,
  last? : Bool = true,
) -> Message raise IppError {
  if !valid_mime_type(format) || document.is_empty() {
    raise Invalid("invalid document format or empty document")
  }
  let request = self.job_request(SendDocument, request_id, job_id)
  let attributes = request.groups[0].attributes
  attributes.push(Attribute::new("document-format", MimeType(format)))
  attributes.push(Attribute::new("last-document", Boolean(last)))
  request.with_document(document)
}
