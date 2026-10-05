///|
pub(all) enum PrinterState {
  Idle
  Processing
  Stopped
  Unrecognized(Int)
} derive(Eq, Debug)

///|
pub extend PrinterState with Eq::{equal, not_equal}

///|
pub extend PrinterState with @debug.Debug::{to_repr}

///|
pub fn printer_state_from_code(code : Int) -> PrinterState {
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
  queued_jobs : Int?
  reasons : Array[String]
  diagnostics : Array[Diagnostic]
} derive(Debug)

///|
pub extend PrinterHealth with @debug.Debug::{to_repr}

///|
pub fn Capabilities::health(self : Capabilities) -> PrinterHealth {
  let state = match self.printer.get_int("printer-state") {
    Some(code) => Some(printer_state_from_code(code))
    None => None
  }
  let accepting_jobs = self.accepting_jobs()
  let reasons = self.strings("printer-state-reasons")
  let diagnostics : Array[Diagnostic] = []
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
    queued_jobs: self.printer.get_int("queued-job-count"),
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
  total : Int
  pending : Int
  held : Int
  processing : Int
  stopped : Int
  canceled : Int
  aborted : Int
  completed : Int
  unknown : Int
} derive(Eq, Debug)

///|
pub extend QueueSummary with Eq::{equal, not_equal}

///|
pub extend QueueSummary with @debug.Debug::{to_repr}

///|
/// Summaries reject duplicate IDs instead of double-counting a malformed queue.
pub fn summarize_queue(jobs : Array[Job]) -> QueueSummary raise IppError {
  let ids : Map[Int, Bool] = Map([])
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
