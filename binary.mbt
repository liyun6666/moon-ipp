///|
priv struct Reader {
  data : Bytes
  mut offset : Int32
  mut limit : Int32
}

///|
fn Reader::new(data : Bytes) -> Reader {
  { data, offset: 0, limit: data.length(), }
}

///|
fn Reader::remaining(self : Reader) -> Int32 {
  self.data.length() - self.offset
}

///|
fn Reader::require(self : Reader, count : Int32) -> Unit raise IppError {
  if count < 0 || count > self.remaining() {
    raise Truncated(self.offset, count)
  }
  if count > self.limit - self.offset {
    raise Limit("message bytes")
  }
}

///|
fn Reader::byte(self : Reader) -> Int32 raise IppError {
  self.require(1)
  let value = self.data[self.offset].to_int()
  self.offset += 1
  value
}

///|
fn Reader::u16(self : Reader) -> Int32 raise IppError {
  let high = self.byte()
  let low = self.byte()
  (high << 8) | low
}

///|
fn Reader::i32(self : Reader) -> Int32 raise IppError {
  let a = self.byte()
  let b = self.byte()
  let c = self.byte()
  let d = self.byte()
  (a << 24) | (b << 16) | (c << 8) | d
}

///|
fn Reader::bytes(self : Reader, count : Int32) -> Bytes raise IppError {
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
  if count > 32767 {
    raise Invalid("negative signed wire length")
  }
  self.bytes(count)
}

///|
fn put_byte(output : @buffer.Buffer, value : Int32) -> Unit raise IppError {
  if value < 0 || value > 255 {
    raise Invalid("byte out of range")
  }
  output.write_byte(value.to_byte())
}

///|
fn put_u16(output : @buffer.Buffer, value : Int32) -> Unit raise IppError {
  if value < 0 || value > 65535 {
    raise Invalid("16-bit value out of range")
  }
  put_byte(output, (value >> 8) & 255)
  put_byte(output, value & 255)
}

///|
fn put_i32(output : @buffer.Buffer, value : Int32) -> Unit raise IppError {
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
  if bytes.length() > 32767 {
    raise Invalid("value exceeds signed wire length")
  }
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
fn encode_utf8(text : String) -> Bytes raise IppError {
  // Native/Wasm UTF-8 encoding aborts on unpaired UTF-16 surrogates, whereas
  // JS replaces them. Reject them first so every backend has the same result.
  let mut index = 0
  while index < text.length() {
    let unit = text[index].to_int()
    if unit >= 0xd800 && unit <= 0xdbff {
      if index + 1 >= text.length() {
        raise Invalid("unpaired UTF-16 surrogate")
      }
      let trail = text[index + 1].to_int()
      if trail < 0xdc00 || trail > 0xdfff {
        raise Invalid("unpaired UTF-16 surrogate")
      }
      index += 2
    } else {
      if unit >= 0xdc00 && unit <= 0xdfff {
        raise Invalid("unpaired UTF-16 surrogate")
      }
      index += 1
    }
  }
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
fn hex_nibble(char : UInt16) -> Int32? {
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
