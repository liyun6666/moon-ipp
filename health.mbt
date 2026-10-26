///|
pub(all) enum PrinterState {
  Idle
  Processing
  Stopped
  Unrecognized(Int32)
} derive(Eq, Debug)

///|
pub extend PrinterState with Eq::{equal, not_equal}

///|
pub extend PrinterState with @debug.Debug::{to_repr}

///|
pub fn printer_state_from_code(code : Int32) -> PrinterState {
  match code {
    3 => Idle
    4 => Processing
    5 => Stopped
    _ => Unrecognized(code)
  }
}

///|
pub fn PrinterState::text(self : PrinterState) -> String {
  match self {
    Idle => "idle"
    Processing => "processing"
    Stopped => "stopped"
    Unrecognized(code) => "unknown-\{code}"
  }
}

///|
pub(all) struct PrinterHealth {
  name : String
  state : PrinterState?
  accepting_jobs : Bool?
  queued_jobs : Int32?
  reasons : Array[String]
  diagnostics : Array[Diagnostic]
} derive(Debug)

///|
pub extend PrinterHealth with @debug.Debug::{to_repr}

///|
// Health is intentionally non-throwing. Malformed status is reported as an
// error diagnostic rather than selecting one of several conflicting values.
fn printer_attribute_issues(printer : Group) -> Array[Diagnostic] {
  let issues : Array[Diagnostic] = []
  validate_attribute_set(printer.attributes) catch {
    _ =>
      issues.push({
        severity: Error,
        attribute: "printer-attributes",
        message: "invalid or conflicting printer attributes",
      })
  }
  if printer.tag != 4 {
    issues.push({
      severity: Error,
      attribute: "printer-attributes",
      message: "expected printer attribute group",
    })
  }
  for attribute in printer.attributes {
    let valid = match attribute.values {
      [OutOfBand(0x12 | 0x13)] => true
      values =>
        match attribute.name {
          "printer-is-accepting-jobs" => values is [Boolean(_)]
          "printer-state" => values is [Enumeration(code)] && code > 0
          "queued-job-count" => values is [Integer(count)] && count >= 0
          "operations-supported" =>
            !values.is_empty() &&
            values.all(value => value is Enumeration(code) && code > 0)
          "document-format-supported" =>
            !values.is_empty() && values.all(value => value is MimeType(_))
          "printer-resolution-supported" =>
            !values.is_empty() &&
            values.all(value => value is ResolutionValue(_))
          "printer-state-reasons" =>
            !values.is_empty() && values.all(value => value is Keyword(_))
          _ => true
        }
    }
    if !valid {
      issues.push({
        severity: Error,
        attribute: attribute.name,
        message: "invalid printer status type or cardinality: \{attribute.name}",
      })
    }
  }
  issues
}

///|
pub fn Capabilities::health(self : Capabilities) -> PrinterHealth {
  let state = match self.printer.find("printer-state") {
    Some({ values: [Enumeration(code)], .. }) if code > 0 =>
      Some(printer_state_from_code(code))
    _ => None
  }
  let accepting_jobs = self.accepting_jobs()
  let reasons = self.strings("printer-state-reasons")
  let diagnostics = printer_attribute_issues(self.printer)
  match state {
    Some(Stopped) =>
      diagnostics.push({
        severity: Error,
        attribute: "printer-state",
        message: "printer is stopped; inspect state reasons",
      })
    Some(Unrecognized(_)) | None =>
      diagnostics.push({
        severity: Warning,
        attribute: "printer-state",
        message: "printer state is unavailable or unrecognized",
      })
    _ => ()
  }
  if accepting_jobs == Some(false) {
    diagnostics.push({
      severity: Error,
      attribute: "printer-is-accepting-jobs",
      message: "printer is not accepting new jobs",
    })
  }
  for reason in reasons {
    if reason == "none" {
      continue
    }
    let severity = if reason.has_suffix("-error") { Error } else { Warning }
    diagnostics.push({
      severity,
      attribute: "printer-state-reasons",
      message: reason,
    })
  }
  {
    name: self.name(),
    state,
    accepting_jobs,
    reasons,
    diagnostics,
    queued_jobs: match self.printer.find("queued-job-count") {
      Some({ values: [Integer(count)], .. }) if count >= 0 => Some(count)
      _ => None
    },
  }
}

///|
pub fn PrinterHealth::ready(self : PrinterHealth) -> Bool {
  self.accepting_jobs == Some(true) &&
  (self.state == Some(Idle) || self.state == Some(Processing)) &&
  !self.diagnostics.any(fn(item) { item.severity == Error })
}

///|
pub fn PrinterHealth::to_json(self : PrinterHealth) -> Json {
  {
    "name": Json::string(self.name),
    "state": match self.state {
      Some(state) => Json::string(state.text())
      None => Json::null()
    },
    "accepting_jobs": match self.accepting_jobs {
      Some(value) => Json::boolean(value)
      None => Json::null()
    },
    "queued_jobs": match self.queued_jobs {
      Some(value) => json_int(value)
      None => Json::null()
    },
    "ready": Json::boolean(self.ready()),
    "reasons": Json::array(self.reasons.map(value => Json::string(value))),
    "diagnostics": Json::array(self.diagnostics.map(value => value.to_json())),
  }
}

///|
pub(all) struct QueueSummary {
  total : Int32
  pending : Int32
  held : Int32
  processing : Int32
  stopped : Int32
  canceled : Int32
  aborted : Int32
  completed : Int32
  unknown : Int32
} derive(Eq, Debug)

///|
pub extend QueueSummary with Eq::{equal, not_equal}

///|
pub extend QueueSummary with @debug.Debug::{to_repr}

///|
/// Summaries reject duplicate IDs instead of double-counting a malformed queue.
pub fn summarize_queue(jobs : Array[Job]) -> QueueSummary raise IppError {
  let ids : Map[Int32, Bool] = Map([])
  let counts = FixedArray::make(8, 0)
  for job in jobs {
    if ids.contains(job.id) {
      raise Protocol("duplicate job-id in queue response")
    }
    ids[job.id] = true
    let index = match job.state {
      Some(Pending) => 0
      Some(PendingHeld) => 1
      Some(Processing) => 2
      Some(ProcessingStopped) => 3
      Some(Canceled) => 4
      Some(Aborted) => 5
      Some(Completed) => 6
      _ => 7
    }
    counts[index] += 1
  }
  {
    total: jobs.length(),
    pending: counts[0],
    held: counts[1],
    processing: counts[2],
    stopped: counts[3],
    canceled: counts[4],
    aborted: counts[5],
    completed: counts[6],
    unknown: counts[7],
  }
}

///|
pub fn QueueSummary::to_json(self : QueueSummary) -> Json {
  {
    "total": json_int(self.total),
    "pending": json_int(self.pending),
    "held": json_int(self.held),
    "processing": json_int(self.processing),
    "stopped": json_int(self.stopped),
    "canceled": json_int(self.canceled),
    "aborted": json_int(self.aborted),
    "completed": json_int(self.completed),
    "unknown": json_int(self.unknown),
  }
}
