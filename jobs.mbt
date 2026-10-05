///|
pub(all) enum JobState {
  Pending
  PendingHeld
  Processing
  ProcessingStopped
  Canceled
  Aborted
  Completed
  Other(Int)
} derive(Eq, Debug)

///|
pub extend JobState with Eq::{equal, not_equal}

///|
pub extend JobState with @debug.Debug::{to_repr}

///|
pub fn job_state_from_code(code : Int) -> JobState {
  match code {
    3 => Pending
    4 => PendingHeld
    5 => Processing
    6 => ProcessingStopped
    7 => Canceled
    8 => Aborted
    9 => Completed
    _ => Other(code)
  }
}

///|
pub fn JobState::code(self : JobState) -> Int {
  match self {
    Pending => 3
    PendingHeld => 4
    Processing => 5
    ProcessingStopped => 6
    Canceled => 7
    Aborted => 8
    Completed => 9
    Other(code) => code
  }
}

///|
pub fn JobState::name(self : JobState) -> String {
  match self {
    Pending => "pending"
    PendingHeld => "pending-held"
    Processing => "processing"
    ProcessingStopped => "processing-stopped"
    Canceled => "canceled"
    Aborted => "aborted"
    Completed => "completed"
    Other(code) => "unknown-\{code}"
  }
}

///|
pub fn JobState::terminal(self : JobState) -> Bool {
  self == Completed || self == Canceled || self == Aborted
}

///|
pub(all) struct Job {
  id : Int
  uri : String?
  name : String?
  state : JobState?
  reasons : Array[String]
  message : String?
  impressions_completed : Int?
  attributes : Group
} derive(Eq, Debug)

///|
pub extend Job with Eq::{equal, not_equal}

///|
pub extend Job with @debug.Debug::{to_repr}

///|
pub fn Job::from_group(group : Group) -> Job raise IppError {
  if group.tag != 2 {
    raise Protocol("expected job attribute group")
  }
  let id = match group.find("job-id") {
    Some(attribute) =>
      match attribute.values {
        [Integer(id)] if id > 0 => id
        _ => raise Protocol("job group requires one positive integer job-id")
      }
    None => raise Protocol("job group has no positive job-id")
  }
  let reasons = match group.find("job-state-reasons") {
    Some(attribute) => attribute.string_values()
    None => []
  }
  let state = match group.get_int("job-state") {
    Some(code) => Some(job_state_from_code(code))
    None => None
  }
  {
    id,
    uri: group.get_string("job-uri"),
    name: group.get_string("job-name"),
    state,
    reasons,
    message: group.get_string("job-state-message"),
    impressions_completed: group.get_int("job-impressions-completed"),
    attributes: group,
  }
}

///|
pub fn jobs_from_response(response : Message) -> Array[Job] raise IppError {
  if !response.is_success() {
    raise Protocol(status_name(response.code))
  }
  let jobs : Array[Job] = []
  for group in response.groups {
    if group.tag == 2 {
      jobs.push(Job::from_group(group))
    }
  }
  jobs
}

///|
pub fn job_from_response(response : Message) -> Job raise IppError {
  let jobs = jobs_from_response(response)
  if jobs.length() != 1 {
    raise Protocol("expected exactly one job group")
  }
  jobs[0]
}

///|
pub(all) enum SubmissionState {
  NotSent
  Sending
  OutcomeUnknown
  Rejected(Int, String)
  Accepted(Job)
} derive(Eq, Debug)

///|
pub extend SubmissionState with Eq::{equal, not_equal}

///|
pub extend SubmissionState with @debug.Debug::{to_repr}

///|
pub fn SubmissionState::may_submit_again(self : SubmissionState) -> Bool {
  match self {
    NotSent => true
    Sending | OutcomeUnknown | Accepted(_) | Rejected(_, _) => false
  }
}

///|
pub(all) struct JobObservation {
  job : Job
  elapsed_ms : Int
} derive(Eq, Debug)

///|
pub extend JobObservation with Eq::{equal, not_equal}

///|
pub extend JobObservation with @debug.Debug::{to_repr}

///|
pub(all) struct PollPolicy {
  interval_ms : Int
  maximum_polls : Int
} derive(Eq, Debug)

///|
pub extend PollPolicy with Eq::{equal, not_equal}

///|
pub extend PollPolicy with @debug.Debug::{to_repr}

///|
pub fn PollPolicy::defaults() -> PollPolicy {
  { interval_ms: 1000, maximum_polls: 60, }
}

///|
pub fn PollPolicy::validate(self : PollPolicy) -> Unit raise IppError {
  if self.interval_ms < 1 ||
    self.interval_ms > 60000 ||
    self.maximum_polls < 1 ||
    self.maximum_polls > 10000 {
    raise Invalid("invalid polling limits")
  }
  if self.interval_ms > 2147483647 / self.maximum_polls {
    raise Invalid("poll duration overflows")
  }
}

///|
pub fn validate_job_observation(
  previous : Job?,
  current : Job,
) -> Unit raise IppError {
  match previous {
    Some(previous) => {
      if previous.id != current.id {
        raise Protocol("polled response returned a different job-id")
      }
      match previous.state {
        Some(state) if state.terminal() =>
          if current.state != previous.state {
            raise Protocol("terminal job state changed")
          }
        _ => ()
      }
    }
    None => ()
  }
}
