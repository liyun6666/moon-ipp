///|
test "lossless JSON keeps typed values and binary payload" {
  let message = @lib.Message::new(0, 1, [
    @lib.Group::printer([
      @lib.Attribute::new(
        "printer-info",
        @lib.TextWithLanguage("zh", "办公室"),
      ),
      @lib.Attribute::new(
        "printer-resolution",
        @lib.ResolutionValue(@lib.Resolution::dpi(600, 600)),
      ),
      @lib.Attribute::new("copies-supported", @lib.Range(1, 99)),
      @lib.Attribute::new("future-field", @lib.Unknown(0x50, b"\x00\xff")),
      @lib.Attribute::new("unavailable", @lib.OutOfBand(0x13)),
    ]),
  ]).with_document(b"\x00PDF")
  assert_eq(@lib.message_from_json(message.to_json()), message)
}
