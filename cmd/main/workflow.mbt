///|
fn observations_json(observations : Array[@ipp.JobObservation]) -> Json {
  Json::array(
    observations.map(observation => {
      let result : Json = {
        "elapsed_ms": Json::number(observation.elapsed_ms.to_double()),
        "job": observation.job.to_json(),
      }
      result
    }),
  )
}

///|
fn require_completed(
  observations : Array[@ipp.JobObservation],
) -> Unit raise @ipp.IppError {
  match observations.last() {
    Some({ job: { state: Some(@ipp.Completed), .. }, .. }) => ()
    Some({ job, .. }) =>
      raise @ipp.Protocol(
        "job \{job.id} did not complete successfully; inspect its state and reasons",
      )
    None => raise @ipp.Protocol("no job observations returned")
  }
}

///|
fn receipt_json(
  printer : String,
  arguments : @cli.Arguments,
  document_bytes : Int32,
  state : String,
  job : @ipp.Job?,
  observations : Array[@ipp.JobObservation],
  failure : String?,
) -> Json {
  {
    "schema": "moon-ipp.receipt.v1",
    "printer": Json::string(printer),
    "state": Json::string(state),
    "document_bytes": Json::number(document_bytes.to_double()),
    "options": arguments.options.to_json(),
    "job": match job {
      Some(job) => job.to_json()
      None => Json::null()
    },
    "observations": observations_json(observations),
    "error": match failure {
      Some(message) => Json::string(message)
      None => Json::null()
    },
  }
}

///|
async fn reserve_receipt(path : String, value : Json) -> Unit {
  // Exclusive creation refuses reuse before the first network call. A receipt
  // left by a crashed invocation must be reconciled, never silently reused.
  @fs.write_file(
    path,
    value.stringify(indent=2) + "\n",
    create_mode=@fs.CreateNew,
    permission=384,
    sync=@fs.Full,
  )
}

///|
async fn update_receipt(path : String, value : Json) -> Unit {
  let temporary = path + ".moon-ipp-tmp"
  let file = @fs.open(
    temporary,
    mode=@fs.WriteOnly,
    create_mode=@fs.CreateNew,
    permission=384,
  )
  defer {
    file.close()
    @fs.remove(temporary) catch {
      _ => ()
    }
  }
  file.write(value.stringify(indent=2) + "\n")
  file.sync()
  file.close()
  @fs.rename(temporary, path, replace=true)
}

///|
async fn print_document(
  client : @client.Client,
  arguments : @cli.Arguments,
  document : Bytes,
) -> Json {
  let printer = client.endpoint().text()
  let mut state = "prepared"
  let mut job : @ipp.Job? = None
  let mut observations : Array[@ipp.JobObservation] = []
  let snapshot = fn(failure : String?) {
    receipt_json(
      printer,
      arguments,
      document.length(),
      state,
      job,
      observations,
      failure,
    )
  }
  match arguments.output {
    Some(path) => reserve_receipt(path, snapshot(None))
    None => ()
  }
  let mut failure : String? = None
  errdefer {
    if failure is None {
      state = if job is None { "outcome-unknown" } else { "tracking-error" }
      failure = Some(
        "operation interrupted; query the printer before submitting again",
      )
    }
    @async.protect_from_cancel(() => {
      match arguments.output {
        Some(path) =>
          update_receipt(path, snapshot(failure)) catch {
            _ =>
              @stdio.stderr.write(
                "moon-ipp: receipt update failed; keep the existing file and reconcile the printer queue\n",
              ) catch {
                _ => ()
              }
          }
        None => ()
      }
    })
  }
  let result : Result[Json, Error] = try {
    state = "submitting"
    match arguments.output {
      Some(path) => update_receipt(path, snapshot(None))
      None => ()
    }
    let accepted = client.print_job(
      arguments.options,
      document,
      preflight=arguments.preflight,
    )
    job = Some(accepted)
    state = "accepted"
    if arguments.wait || arguments.output is Some(_) {
      @stdio.stderr.write(
        "moon-ipp: accepted job \{accepted.id}; query this job before submitting again\n",
      )
    }
    match arguments.output {
      Some(path) => update_receipt(path, snapshot(None))
      None => ()
    }
    if arguments.wait {
      observations = client.wait_job(accepted.id, policy=@ipp.PollPolicy::{
        interval_ms: arguments.interval_ms,
        maximum_polls: arguments.polls,
      })
      state = match observations.last() {
        Some({ job: final_job, .. }) => {
          job = Some(final_job)
          match final_job.state {
            Some(terminal) => terminal.name()
            None => "tracking-error"
          }
        }
        _ => "tracking-error"
      }
      match arguments.output {
        Some(path) => update_receipt(path, snapshot(None))
        None => ()
      }
      require_completed(observations)
    }
    if arguments.wait || arguments.output is Some(_) {
      snapshot(None)
    } else {
      accepted.to_json()
    }
  } catch {
    error => Err(error)
  } noraise {
    value => Ok(value)
  }
  match result {
    Ok(value) => value
    Err(error) => {
      if job is None {
        state = if error is @client.SubmissionUncertain(_) {
          "outcome-unknown"
        } else {
          "not-submitted"
        }
      } else if state != "completed" &&
        state != "canceled" &&
        state != "aborted" {
        state = "tracking-error"
      }
      failure = Some(describe_error(error))
      raise error
    }
  }
}
