///|
fn main {
  try {
    let context = @ipp.RequestContext::new("ipp://localhost:8631/ipp/print")
    let request = context.printer_attributes(1, requested=["printer-name"])
    let bytes = @ipp.encode(request)
    let decoded = @ipp.decode(bytes)
    assert_eq(decoded, request)
    println("Get-Printer-Attributes bytes: \{bytes.length()}")
    println(@ipp.hex_dump(bytes))
  } catch {
    error => {
      println("packet example failed: \{error}")
      panic()
    }
  }
}
