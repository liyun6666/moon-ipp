///|
extern "C" fn exit_process(code : Int) -> Unit = "exit"

///|
async fn read_bytes(path : String, maximum : Int) -> Bytes {
  let file = @fs.open(path, mode=@fs.ReadOnly)
  defer file.close()
  if file.size() > maximum.to_int64() {
    raise @ipp.Limit("input file bytes")
  }
  let buffer = @buffer.Buffer()
  while true {
    match file.read_some(max_len=8192) {
      None => break
      Some(chunk) => {
        if chunk.length() > maximum - buffer.length() {
          raise @ipp.Limit("input file bytes")
        }
        buffer.write_bytes(chunk)
      }
    }
  }
  buffer.to_bytes()
}

///|
async fn read_json(path : String) -> Json {
  let bytes = read_bytes(path, 1048576)
  let text = @utf8.decode(bytes)
  @json.parse(text)
}

///|
async fn emit(json : Json, path : String?) -> Unit {
  let text = json.stringify(indent=2) + "\n"
  match path {
    Some(path) => @fs.write_file(path, text)
    None => @stdio.stdout.write(text)
  }
}

///|
fn required_path(value : String?) -> String raise @ipp.IppError {
  match value {
    Some(path) => path
    None => raise @ipp.Invalid("missing required path")
  }
}

///|
fn required_id(value : Int?) -> Int raise @ipp.IppError {
  match value {
    Some(id) => id
    None => raise @ipp.Invalid("missing required job ID")
  }
}

///|
async fn execute(arguments : @cli.Arguments) -> Unit {
  match arguments.command {
    @cli.Help => {
      @stdio.stdout.write(@cli.help() + "\n")
      return
    }
    @cli.Version => {
      @stdio.stdout.write("moon-ipp 0.1.0\n")
      return
    }
    @cli.Decode => {
      let message = @ipp.decode(
        read_bytes(required_path(arguments.input), 17825792),
      )
      emit(message.to_json(), arguments.output)
      return
    }
    @cli.Encode => {
      let message = @ipp.message_from_json(
        read_json(required_path(arguments.input)),
      )
      @fs.write_file(required_path(arguments.output), @ipp.encode(message))
      return
    }
    @cli.Compare => {
      let before = @ipp.Capabilities::from_response(
        @ipp.message_from_json(read_json(required_path(arguments.input))),
      )
      let after = @ipp.Capabilities::from_response(
        @ipp.message_from_json(read_json(required_path(arguments.other))),
      )
      let changes = @ipp.compare_capabilities(before, after)
      emit(Json::array(changes.map(change => change.to_json())), None)
      return
    }
    _ => ()
  }
  let transport = @client.HttpTransport::new(
    authorization?=@env.get_env_var("MOON_IPP_AUTHORIZATION"),
  )
  let client = @client.Client::new(
    required_path(arguments.uri),
    transport,
    user=arguments.user,
    timeout_ms=arguments.timeout_ms,
  )
  match arguments.command {
    @cli.Capabilities =>
      emit(
        client.printer_attributes(requested=arguments.requested).to_json(),
        None,
      )
    @cli.Health => emit(client.capabilities().health().to_json(), None)
    @cli.Jobs => {
      let jobs = client.jobs(
        which=arguments.which,
        mine=arguments.mine,
        limit=arguments.limit,
      )
      let result : Json = {
        "summary": @ipp.summarize_queue(jobs).to_json(),
        "jobs": Json::array(jobs.map(job => job.to_json())),
      }
      emit(result, None)
    }
    @cli.Job => emit(client.job(required_id(arguments.job_id)).to_json(), None)
    @cli.Cancel =>
      emit(client.cancel_job(required_id(arguments.job_id)).to_json(), None)
    @cli.Print => {
      let document = read_bytes(required_path(arguments.input), 16777216)
      let job = client.print_job(
        arguments.options,
        document,
        preflight=arguments.preflight,
      )
      emit(job.to_json(), None)
    }
    @cli.Validate =>
      emit(client.validate_job(arguments.options).to_json(), None)
    @cli.Create => emit(client.create_job(arguments.options).to_json(), None)
    @cli.Send => {
      let document = read_bytes(required_path(arguments.input), 16777216)
      let response = client.send_document(
        required_id(arguments.job_id),
        arguments.options.document_format,
        document,
        last=arguments.last_document,
      )
      emit(response.to_json(), None)
    }
    @cli.Wait => {
      let observations = client.wait_job(required_id(arguments.job_id), policy=@ipp.PollPolicy::{
        interval_ms: arguments.interval_ms,
        maximum_polls: arguments.polls,
      })
      emit(
        Json::array(
          observations.map(observation => {
            let result : Json = {
              "elapsed_ms": Json::number(observation.elapsed_ms.to_double()),
              "job": observation.job.to_json(),
            }
            result
          }),
        ),
        None,
      )
    }
    _ => raise @ipp.Invalid("unexpected command")
  }
}

///|
fn describe_error(error : Error) -> String {
  match error {
    @ipp.Invalid(message) => "invalid input: \{message}"
    @ipp.Protocol(message) => "IPP response error: \{message}"
    @ipp.Unsupported(message) => "unsupported: \{message}"
    @ipp.Limit(message) => "resource limit: \{message}"
    @ipp.Truncated(offset, count) =>
      "truncated IPP at byte \{offset}, needed \{count} bytes"
    @client.HttpStatus(code) => "HTTP status \{code}"
    @client.UnexpectedContentType(value) =>
      "expected application/ipp; received \{value}"
    @client.ResponseTooLarge => "HTTP response exceeds configured byte limit"
    @client.ConcurrentRequest => "client already has a request in progress"
    @client.SubmissionUncertain(message) =>
      "submission outcome unknown: \{message}"
    @client.JobWaitExpired(id) => "polling limit reached for job \{id}"
    _ => "\{error}"
  }
}

///|
async fn main {
  let args = @env.args()
  let user_args = if args.is_empty() { [] } else { args[1:].to_owned() }
  execute(@cli.parse(user_args)) catch {
    error => {
      @stdio.stderr.write("moon-ipp: \{describe_error(error)}\n") catch {
        _ => ()
      }
      exit_process(1)
    }
  }
}
