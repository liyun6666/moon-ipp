///|
pub(all) enum Operation {
  PrintJob
  ValidateJob
  CreateJob
  SendDocument
  CancelJob
  GetJobAttributes
  GetJobs
  GetPrinterAttributes
} derive(Eq, Debug)

///|
pub extend Operation with Eq::{equal, not_equal}

///|
pub extend Operation with @debug.Debug::{to_repr}

///|
pub fn Operation::code(self : Operation) -> Int {
  match self {
    PrintJob => 0x0002
    ValidateJob => 0x0004
    CreateJob => 0x0005
    SendDocument => 0x0006
    CancelJob => 0x0008
    GetJobAttributes => 0x0009
    GetJobs => 0x000a
    GetPrinterAttributes => 0x000b
  }
}

///|
pub fn Operation::name(self : Operation) -> String {
  match self {
    PrintJob => "Print-Job"
    ValidateJob => "Validate-Job"
    CreateJob => "Create-Job"
    SendDocument => "Send-Document"
    CancelJob => "Cancel-Job"
    GetJobAttributes => "Get-Job-Attributes"
    GetJobs => "Get-Jobs"
    GetPrinterAttributes => "Get-Printer-Attributes"
  }
}

///|
pub fn operation_from_code(code : Int) -> Operation? {
  match code {
    2 => Some(PrintJob)
    4 => Some(ValidateJob)
    5 => Some(CreateJob)
    6 => Some(SendDocument)
    8 => Some(CancelJob)
    9 => Some(GetJobAttributes)
    10 => Some(GetJobs)
    11 => Some(GetPrinterAttributes)
    _ => None
  }
}

///|
pub fn status_name(code : Int) -> String {
  match code {
    0x0000 => "successful-ok"
    0x0001 => "successful-ok-ignored-or-substituted-attributes"
    0x0002 => "successful-ok-conflicting-attributes"
    0x0400 => "client-error-bad-request"
    0x0401 => "client-error-forbidden"
    0x0402 => "client-error-not-authenticated"
    0x0403 => "client-error-not-authorized"
    0x0404 => "client-error-not-possible"
    0x0405 => "client-error-timeout"
    0x0406 => "client-error-not-found"
    0x0407 => "client-error-gone"
    0x0408 => "client-error-request-entity-too-large"
    0x0409 => "client-error-request-value-too-long"
    0x040a => "client-error-document-format-not-supported"
    0x040b => "client-error-attributes-or-values-not-supported"
    0x040c => "client-error-uri-scheme-not-supported"
    0x040d => "client-error-charset-not-supported"
    0x040e => "client-error-conflicting-attributes"
    0x040f => "client-error-compression-not-supported"
    0x0410 => "client-error-compression-error"
    0x0411 => "client-error-document-format-error"
    0x0412 => "client-error-document-access-error"
    0x0500 => "server-error-internal-error"
    0x0501 => "server-error-operation-not-supported"
    0x0502 => "server-error-service-unavailable"
    0x0503 => "server-error-version-not-supported"
    0x0504 => "server-error-device-error"
    0x0505 => "server-error-temporary-error"
    0x0506 => "server-error-not-accepting-jobs"
    0x0507 => "server-error-busy"
    0x0508 => "server-error-job-canceled"
    0x0509 => "server-error-multiple-document-jobs-not-supported"
    _ => "unknown-status-\{code}"
  }
}

///|
pub fn group_name(tag : Int) -> String {
  match tag {
    1 => "operation-attributes"
    2 => "job-attributes"
    4 => "printer-attributes"
    5 => "unsupported-attributes"
    6 => "subscription-attributes"
    7 => "event-notification-attributes"
    8 => "resource-attributes"
    9 => "document-attributes"
    10 => "system-attributes"
    _ => "unknown-group-\{tag}"
  }
}

///|
pub fn value_tag_name(tag : Int) -> String {
  match tag {
    0x10 => "unsupported"
    0x12 => "unknown"
    0x13 => "no-value"
    0x15 => "not-settable"
    0x16 => "delete-attribute"
    0x17 => "admin-define"
    0x21 => "integer"
    0x22 => "boolean"
    0x23 => "enum"
    0x30 => "octetString"
    0x31 => "dateTime"
    0x32 => "resolution"
    0x33 => "rangeOfInteger"
    0x34 => "collection"
    0x35 => "textWithLanguage"
    0x36 => "nameWithLanguage"
    0x41 => "textWithoutLanguage"
    0x42 => "nameWithoutLanguage"
    0x44 => "keyword"
    0x45 => "uri"
    0x46 => "uriScheme"
    0x47 => "charset"
    0x48 => "naturalLanguage"
    0x49 => "mimeMediaType"
    _ => "unknown-tag-\{tag}"
  }
}

///|
pub fn is_safe_to_retry(operation : Operation) -> Bool {
  match operation {
    GetPrinterAttributes | GetJobAttributes | GetJobs | ValidateJob => true
    PrintJob | CreateJob | SendDocument | CancelJob => false
  }
}
