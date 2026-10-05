///|
pub struct Client {
  context : @ipp.RequestContext
  transport : &Transport
  timeout_ms : Int
  limits : @ipp.DecodeLimits
  mut next_id : Int
  mut busy : Bool
}

///|
pub fn Client::new(
  uri : String,
  transport : &Transport,
  user? : String = "anonymous",
  timeout_ms? : Int = 10000,
  limits? : @ipp.DecodeLimits = @ipp.DecodeLimits::defaults(),
) -> Client raise @ipp.IppError {
  if timeout_ms < 1 || timeout_ms > 300000 {
    raise @ipp.Invalid("timeout must be between 1 and 300000 ms")
  }
  limits.validate()
  {
    context: @ipp.RequestContext::new(uri, user~),
    transport,
    timeout_ms,
    limits,
    next_id: 1,
    busy: false,
  }
}

///|
fn Client::request_id(self : Client) -> Int {
  let current = self.next_id
  self.next_id = if current == 2147483647 { 1 } else { current + 1 }
  current
}

///|
pub fn Client::endpoint(self : Client) -> @ipp.PrinterUri {
  self.context.printer
}

///|
pub async fn Client::exchange(
  self : Client,
  request : @ipp.Message,
) -> @ipp.Message {
  if self.busy {
    raise ConcurrentRequest
  }
  @ipp.validate_request(request)
  let payload = @ipp.encode(request, limits=self.limits)
  let operation = match @ipp.operation_from_code(request.code) {
    Some(operation) => operation
    None => raise @ipp.Unsupported("operation")
  }
  self.busy = true
  defer {
    self.busy = false
  }
  let response = try {
    let bytes = @async.with_timeout(self.timeout_ms, async fn() {
      self.transport.exchange(
        self.context.printer,
        payload,
        self.limits.max_message_bytes,
      )
    })
    let response = @ipp.decode(bytes, limits=self.limits)
    @ipp.validate_response(request, response)
    response
  } catch {
    error =>
      match operation {
        @ipp.PrintJob | @ipp.CreateJob | @ipp.SendDocument =>
          raise SubmissionUncertain(
            "transport or response validation failed; query jobs before submitting again",
          )
        _ => raise error
      }
  }
  @ipp.require_success(response)
  response
}

///|
pub async fn Client::printer_attributes(
  self : Client,
  requested? : Array[String] = [],
) -> @ipp.Message {
  self.exchange(self.context.printer_attributes(self.request_id(), requested~))
}

///|
pub async fn Client::capabilities(self : Client) -> @ipp.Capabilities {
  @ipp.Capabilities::from_response(self.printer_attributes())
}

///|
pub async fn Client::validate_job(
  self : Client,
  options : @ipp.JobOptions,
) -> @ipp.Message {
  self.exchange(self.context.validate_job(self.request_id(), options))
}

///|
pub async fn Client::print_job(
  self : Client,
  options : @ipp.JobOptions,
  document : Bytes,
  preflight? : Bool = true,
) -> @ipp.Job {
  if document.length() > self.limits.max_document_bytes {
    raise @ipp.Limit("document bytes")
  }
  if preflight {
    let capabilities = self.capabilities()
    capabilities.require_options(options, document_bytes=document.length())
    if capabilities.supports_operation(@ipp.ValidateJob) != Some(false) {
      let _ = self.validate_job(options)
    }
  }
  @ipp.job_from_response(
    self.exchange(self.context.print_job(self.request_id(), options, document)),
  )
}

///|
pub async fn Client::create_job(
  self : Client,
  options : @ipp.JobOptions,
) -> @ipp.Job {
  @ipp.job_from_response(
    self.exchange(self.context.create_job(self.request_id(), options)),
  )
}

///|
pub async fn Client::send_document(
  self : Client,
  job_id : Int,
  format : String,
  document : Bytes,
  last? : Bool = true,
) -> @ipp.Message {
  self.exchange(
    self.context.send_document(
      self.request_id(),
      job_id,
      format,
      document,
      last~,
    ),
  )
}

///|
pub async fn Client::job(self : Client, job_id : Int) -> @ipp.Job {
  @ipp.job_from_response(
    self.exchange(self.context.job_attributes(self.request_id(), job_id)),
  )
}

///|
pub async fn Client::jobs(
  self : Client,
  which? : String = "not-completed",
  mine? : Bool = false,
  limit? : Int = 100,
) -> Array[@ipp.Job] {
  @ipp.jobs_from_response(
    self.exchange(
      self.context.get_jobs(self.request_id(), which~, mine~, limit~),
    ),
  )
}

///|
pub async fn Client::cancel_job(self : Client, job_id : Int) -> @ipp.Message {
  self.exchange(self.context.cancel_job(self.request_id(), job_id))
}

///|
pub async fn Client::wait_job(
  self : Client,
  job_id : Int,
  policy? : @ipp.PollPolicy = @ipp.PollPolicy::defaults(),
) -> Array[@ipp.JobObservation] {
  policy.validate()
  let observations : Array[@ipp.JobObservation] = []
  let mut previous : @ipp.Job? = None
  for index = 0; index < policy.maximum_polls; index = index + 1 {
    let job = self.job(job_id)
    @ipp.validate_job_observation(previous, job)
    observations.push({ job, elapsed_ms: index * policy.interval_ms, })
    match job.state {
      Some(state) if state.terminal() => return observations
      _ => ()
    }
    previous = Some(job)
    if index + 1 < policy.maximum_polls {
      @async.sleep(policy.interval_ms)
    }
  }
  raise JobWaitExpired(job_id)
}
