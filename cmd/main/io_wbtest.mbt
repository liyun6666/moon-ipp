///|
async test "JSON files reject duplicate keys instead of silently choosing a target" {
  let path = "_build/cli-duplicate-json-test.json"
  @fs.mkdir("_build", allow_exist=true)
  @fs.write_file(path, "{\"request_id\":1,\"request_id\":2}")
  defer @fs.remove(path)
  try read_json(path) catch {
    _ => ()
  } noraise {
    _ => fail("ambiguous JSON keys accepted")
  }
}

///|
async test "JSON depth is bounded before importing attributes" {
  let path = "_build/cli-depth-json-test.json"
  @fs.mkdir("_build", allow_exist=true)
  @fs.write_file(path, "[".repeat(129) + "0" + "]".repeat(129))
  defer @fs.remove(path)
  try read_json(path) catch {
    _ => ()
  } noraise {
    _ => fail("excessive JSON nesting accepted")
  }
}

///|
async test "file byte bounds accept the exact limit and reject one extra byte" {
  let path = "_build/cli-bytes-test.ipp"
  @fs.mkdir("_build", allow_exist=true)
  let data = b"\x00\x03\xff"
  @fs.write_file(path, data)
  defer @fs.remove(path)
  assert_eq(read_bytes(path, 3), data)
  try read_bytes(path, 2) catch {
    error => assert_true(error is @ipp.Limit(_))
  } noraise {
    _ => fail("oversized file accepted")
  }
}
