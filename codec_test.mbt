///|
test "RFC compatible minimal response byte vector" {
  let bytes = @lib.bytes_from_hex(
    "020000000000000101470012617474726962757465732d6368617273657400057574662d3803",
  )
  let message = @lib.decode(bytes)
  assert_eq(message.request_id, 1)
  assert_eq(message.groups[0].get_string("attributes-charset"), Some("utf-8"))
  assert_eq(@lib.encode(message), bytes)
}

///|
test "collection and binary document round trip" {
  let message = @lib.Message::new(2, 123, [
    @lib.Group::job([
      @lib.Attribute::new(
        "media-col",
        @lib.Collection([
          @lib.Attribute::new(
            "media-size",
            @lib.Collection([
              @lib.Attribute::new("x-dimension", @lib.Integer(21000)),
              @lib.Attribute::new("y-dimension", @lib.Integer(29700)),
            ]),
          ),
        ]),
      ),
      @lib.Attribute::keywords("job-state-reasons", ["none", "job-printing"]),
      @lib.Attribute::new("unknown-extension", @lib.Unknown(0x50, b"\x00\xff")),
    ]),
  ]).with_document(b"\x03\x00\xffPDF")
  assert_eq(@lib.decode(@lib.encode(message)), message)
}

///|
test "signed integer boundaries survive wire representation" {
  let message = @lib.Message::new(0, 1, [
    @lib.Group::job([
      @lib.Attribute::integers("numbers", [-2147483648, -1, 0, 2147483647]),
    ]),
  ])
  assert_eq(@lib.decode(@lib.encode(message)), message)
}
