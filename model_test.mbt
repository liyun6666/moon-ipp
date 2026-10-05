///|
test "typed model retains attribute order and null lookup" {
  let group = @lib.Group::printer([
    @lib.Attribute::new("printer-name", @lib.Name("Office")),
    @lib.Attribute::new("printer-state", @lib.Enumeration(3)),
  ])
  assert_eq(group.get_string("printer-name"), Some("Office"))
  assert_eq(group.get_int("printer-state"), Some(3))
  assert_eq(group.get_bool("missing"), None)
  assert_eq(@lib.bytes_to_hex(@lib.bytes_from_hex("aB0123")), "ab0123")
}
