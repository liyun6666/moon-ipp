///| A bounded collector for one HTTP body. IPP has no outer message-length field;

///|
/// finish must be called at HTTP EOF, not when a 0x03 byte appears in a document.
pub struct MessageCollector {
  limits : DecodeLimits
  buffer : @buffer.Buffer
  mut closed : Bool
}

///|
pub fn MessageCollector::new(
  limits? : DecodeLimits = DecodeLimits::defaults(),
) -> MessageCollector raise IppError {
  limits.validate()
  if limits.max_message_bytes > 2147483647 - limits.max_document_bytes {
    raise Invalid("combined collector limits exceed integer range")
  }
  { limits, buffer: @buffer.Buffer(), closed: false, }
}

///|
pub fn MessageCollector::feed(
  self : MessageCollector,
  chunk : Bytes,
) -> Unit raise IppError {
  if self.closed {
    raise Invalid("collector is already finished")
  }
  let maximum = self.limits.max_message_bytes + self.limits.max_document_bytes
  if chunk.length() > maximum - self.buffer.length() {
    raise Limit("HTTP body bytes")
  }
  self.buffer.write_bytes(chunk)
}

///|
pub fn MessageCollector::length(self : MessageCollector) -> Int {
  self.buffer.length()
}

///|
pub fn MessageCollector::finish(
  self : MessageCollector,
) -> Message raise IppError {
  if self.closed {
    raise Invalid("collector is already finished")
  }
  self.closed = true
  decode(self.buffer.to_bytes(), limits=self.limits)
}

///| A hex dump reports offsets independently of UTF-8 decoding, including binary

///|
/// document bytes. The output limit prevents an accidental multi-megabyte log.
pub fn hex_dump(
  bytes : Bytes,
  maximum? : Int = 1024,
  width? : Int = 16,
) -> String raise IppError {
  if maximum < 0 || maximum > 1048576 || width < 1 || width > 64 {
    raise Invalid("invalid hex dump limits")
  }
  let output = StringBuilder()
  let count = if bytes.length() < maximum { bytes.length() } else { maximum }
  let mut offset = 0
  while offset < count {
    let address = offset.reinterpret_as_uint().to_string(radix=16)
    for pad = address.length(); pad < 8; pad = pad + 1 {
      output.write_string("0")
    }
    output.write_string(address)
    output.write_string("  ")
    let end = if count - offset < width { count } else { offset + width }
    for index = offset; index < offset + width; index = index + 1 {
      if index < end {
        output.write_string(
          bytes_to_hex(bytes.exact_view(start=index, end=index + 1).to_owned()),
        )
      } else {
        output.write_string("  ")
      }
      output.write_string(" ")
    }
    output.write_string(" |")
    for index = offset; index < end; index = index + 1 {
      let byte = bytes[index].to_int()
      if byte >= 32 && byte <= 126 {
        output.write_char(byte.to_char().unwrap())
      } else {
        output.write_string(".")
      }
    }
    output.write_string("|\n")
    offset = end
  }
  if count < bytes.length() {
    output.write_string("... \{bytes.length() - count} bytes omitted\n")
  }
  output.to_string()
}
