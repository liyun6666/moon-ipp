///|
test "versions and resource limits" {
  assert_eq(@lib.Version::v11().text(), "1.1")
  assert_eq(@lib.Version::new(2, 0), @lib.Version::v20())
  @lib.DecodeLimits::defaults().validate()
}
