///|
test "strict parser builds a document print request" {
  let args = parse([
    "print", "--uri=ipp://printer/ipp/print", "--input", "report.PDF", "--copies",
    "2", "--sides", "two-sided-long-edge", "--pages", "1-3,5", "--resolution", "600x300",
  ])
  assert_eq(args.options.document_format, "application/pdf")
  assert_eq(args.options.copies, 2)
  assert_eq(args.options.page_ranges.length(), 2)
  assert_eq(args.options.resolution, Some(@ipp.Resolution::dpi(600, 300)))
  assert_eq(args.preflight, true)
}

///|
test "mistyped duplicate missing and inapplicable options fail" {
  for
    args in [
      ["print", "--uri", "ipp://host/x"],
      ["print", "--uri", "ipp://host/x", "--input", "a.pdf", "--copise", "2"],
      ["job", "--uri", "ipp://host/x", "--job-id", "0"],
      ["jobs", "--uri", "ipp://host/x", "--copies", "2"],
      ["jobs", "--uri", "ipp://host/x", "--mine=false"],
      ["jobs", "--uri", "ipp://host/x", "--limit", "1", "--limit", "2"],
      ["wait", "--uri", "ipp://host/x", "--job-id", "1", "--timeout", "300001"],
      ["encode", "--input", "a.json"],
    ] {
    try parse(args) catch {
      _ => ()
    } noraise {
      _ => fail("invalid CLI options accepted")
    }
  }
}

///|
test "offline and queue commands retain their own arguments" {
  let args = parse([
    "jobs", "--uri", "ipp://host/x", "--which", "completed", "--mine", "--limit",
    "3",
  ])
  assert_eq(args.which, "completed")
  assert_eq(args.mine, true)
  assert_eq(args.limit, 3)
  assert_eq(parse(["decode", "--input", "dump.ipp"]).uri, None)
  assert_eq(parse([]).command, Help)
}
