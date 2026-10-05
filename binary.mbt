///|
priv struct Reader {
  data : Bytes
  mut offset : Int
}

///|
fn Reader::new(data : Bytes) -> Reader {
  { data, offset: 0, }
}

///|
fn Reader::remaining(self : Reader) -> Int {
  self.data.length() - self.offset
}

///|
fn Reader::require(self : Reader, count : Int) -> Unit raise IppError {
  if count < 0 || count > self.remaining() {
    raise Truncated(self.offset, count)
  }
}

///|
fn Reader::byte(self : Reader) -> Int raise IppError {
  self.require(1)
  let value = self.data[self.offset].to_int()
  self.offset += 1
  value
}

///|
fn Reader::u16(self : Reader) -> Int raise IppError {
  let high = self.byte()
  let low = self.byte()
  (high << 8) | low
}

///|
fn Reader::i32(self : Reader) -> Int raise IppError {
  let a = self.byte()
  let b = self.byte()
  let c = self.byte()
  let d = self.byte()
  (a << 24) | (b << 16) | (c << 8) | d
}

///|
fn Reader::bytes(self : Reader, count : Int) -> Bytes raise IppError {
  self.require(count)
  let bytes = self.data
    .exact_view(start=self.offset, end=self.offset + count)
    .to_owned()
  self.offset += count
  bytes
}

///|
fn Reader::length_bytes(self : Reader) -> Bytes raise IppError {
  let count = self.u16()
  self.bytes(count)
}

///|
fn Reader::peek(self : Reader) -> Int raise IppError {
  self.require(1)
  self.data[self.offset].to_int()
}

///|
fn put_byte(output : @buffer.Buffer, value : Int) -> Unit raise IppError {
  if value < 0 || value > 255 {
    raise Invalid("byte out of range")
  }
  output.write_byte(value.to_byte())
}

///|
fn put_u16(output : @buffer.Buffer, value : Int) -> Unit raise IppError {
  if value < 0 || value > 65535 {
    raise Invalid("16-bit value out of range")
  }
  put_byte(output, (value >> 8) & 255)
  put_byte(output, value & 255)
}

///|
fn put_i32(output : @buffer.Buffer, value : Int) -> Unit raise IppError {
  put_byte(output, (value >> 24) & 255)
  put_byte(output, (value >> 16) & 255)
  put_byte(output, (value >> 8) & 255)
  put_byte(output, value & 255)
}

///|
fn put_length_bytes(
  output : @buffer.Buffer,
  bytes : Bytes,
) -> Unit raise IppError {
  put_u16(output, bytes.length())
  output.write_bytes(bytes)
}

///|
fn decode_utf8(bytes : Bytes) -> String raise IppError {
  @utf8.decode(bytes) catch {
    _ => raise Invalid("malformed UTF-8 in attribute")
  }
}

///|
fn encode_utf8(text : String) -> Bytes {
  @utf8.encode(text)
}

///|
pub fn bytes_to_hex(bytes : Bytes) -> String {
  let out = StringBuilder()
  let digits = "0123456789abcdef"
  for byte in bytes {
    let n = byte.to_int()
    out.write_char(digits[n >> 4].to_char().unwrap())
    out.write_char(digits[n & 15].to_char().unwrap())
  }
  out.to_string()
}

///|
fn hex_nibble(char : UInt16) -> Int? {
  let n = char.to_int()
  if n >= 48 && n <= 57 {
    Some(n - 48)
  } else if n >= 65 && n <= 70 {
    Some(n - 55)
  } else if n >= 97 && n <= 102 {
    Some(n - 87)
  } else {
    None
  }
}

///|
pub fn bytes_from_hex(text : String) -> Bytes raise IppError {
  if text.length() % 2 != 0 {
    raise Invalid("hex input has odd length")
  }
  let output = @buffer.Buffer()
  for i = 0; i < text.length(); i = i + 2 {
    let high = match hex_nibble(text[i]) {
      Some(value) => value
      None => raise Invalid("invalid hex digit at \{i}")
    }
    let low = match hex_nibble(text[i + 1]) {
      Some(value) => value
      None => raise Invalid("invalid hex digit at \{i + 1}")
    }
    put_byte(output, high * 16 + low)
  }
  output.to_bytes()
}
