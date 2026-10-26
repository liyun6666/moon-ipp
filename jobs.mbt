///|
pub(all) enum JobState {
  Pending
  PendingHeld
  Processing
  ProcessingStopped
  Canceled
  Aborted
  Completed
  Other(Int32)
} derive(Eq, Debug)

///|
pub extend JobState with Eq::{equal, not_equal}

///|
pub extend JobState with @debug.Debug::{to_repr}

///|
pub fn job_state_from_code(code : Int32) -> JobState {
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
pub fn JobState::code(self : JobState) -> Int32 {
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
  id : Int32
  uri : String?
  name : String?
  state : JobState?
  reasons : Array[String]
  message : String?
  impressions_completed : Int32?
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
  validate_attribute_set(group.attributes)
  let id = match group.find("job-id") {
    Some(attribute) =>
      match attribute.values {
        [Integer(id)] if id > 0 => id
        _ => raise Protocol("job group requires one positive integer job-id")
      }
    None => raise Protocol("job group has no positive job-id")
  }
  let reasons = match group.find("job-state-reasons") {
    Some({ values: [OutOfBand(0x12 | 0x13)], .. }) => []
    Some(attribute) =>
      attribute.values.map(value => {
        match value {
          Keyword(reason) => reason
          _ => raise Protocol("job-state-reasons requires keyword values")
        }
      })
    None => []
  }
  let state = match group.find("job-state") {
    Some(attribute) =>
      match attribute.values {
        [Enumeration(code)] if code > 0 => Some(job_state_from_code(code))
        [OutOfBand(0x12 | 0x13)] => None
        _ => raise Protocol("job-state requires one enumeration value")
      }
    None => None
  }
  let impressions_completed = match group.find("job-impressions-completed") {
    Some(attribute) =>
      match attribute.values {
        [Integer(count)] if count >= 0 => Some(count)
        [OutOfBand(0x12 | 0x13)] => None
        _ =>
          raise Protocol(
            "job-impressions-completed requires one nonnegative integer",
          )
      }
    None => None
  }
  {
    id,
    uri: job_optional_string(group, "job-uri", 0x45),
    name: job_optional_string(group, "job-name", 0x42),
    state,
    reasons,
    message: job_optional_string(group, "job-state-message", 0x41),
    impressions_completed,
    attributes: group,
  }
}

///|
fn job_optional_string(
  group : Group,
  name : String,
  tag : Int32,
) -> String? raise IppError {
  match group.find(name) {
    None => None
    Some(attribute) =>
      match attribute.values {
        [OutOfBand(0x12 | 0x13)] => None
        [value] if value.tag() == tag ||
          (tag == 0x42 && value.tag() == 0x36) ||
          (tag == 0x41 && value.tag() == 0x35) => value.as_string()
        _ => raise Protocol("\{name} has invalid type or cardinality")
      }
  }
}

///|
pub fn jobs_from_response(response : Message) -> Array[Job] raise IppError {
  if !response.is_success() {
    raise Protocol(status_name(response.code))
  }
  let jobs : Array[Job] = []
  let seen : Map[Int32, Bool] = Map([])
  for group in response.groups {
    if group.tag == 2 {
      let job = Job::from_group(group)
      if seen.contains(job.id) {
        raise Protocol("repeated job-id in response")
      }
      seen[job.id] = true
      jobs.push(job)
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
  Rejected(Int32, String)
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
  elapsed_ms : Int32
} derive(Eq, Debug)

///|
pub extend JobObservation with Eq::{equal, not_equal}

///|
pub extend JobObservation with @debug.Debug::{to_repr}

///|
pub(all) struct PollPolicy {
  interval_ms : Int32
  maximum_polls : Int32
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
