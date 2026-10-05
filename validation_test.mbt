///|
test "job requests preserve RFC 8011 target ordering on the wire" {
  let context = @lib.RequestContext::new("ipp://localhost/ipp/print")
  for
    request in [
      context.job_attributes(1, 27),
      context.cancel_job(2, 27),
      context.send_document(3, 27, "application/pdf", b"pdf"),
    ] {
    let decoded = @lib.decode(@lib.encode(request))
    assert_eq(decoded.groups[0].attributes[2].name, "printer-uri")
    assert_eq(decoded.groups[0].attributes[3].name, "job-id")
    @lib.validate_request(decoded)
    let attributes = decoded.groups[0].attributes.copy()
    let target = attributes[2]
    attributes[2] = attributes[4]
    attributes[4] = target
    let misplaced = @lib.Message::{
      ..decoded,
      groups: [@lib.Group::operation(attributes)],
    }
    try @lib.validate_request(misplaced) catch {
      _ => ()
    } noraise {
      _ => fail("out-of-order target accepted")
    }
    let wrong_job_order = decoded.groups[0].attributes.copy()
    let job = wrong_job_order[3]
    wrong_job_order[3] = wrong_job_order[4]
    wrong_job_order[4] = job
    try
      @lib.validate_request(@lib.Message::{
        ..decoded,
        groups: [@lib.Group::operation(wrong_job_order)],
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("out-of-order job-id accepted")
    }
  }
}

///|
fn replace_operation_value(
  request : @lib.Message,
  attribute : @lib.Attribute,
) -> @lib.Message {
  let groups = request.groups.map(group => {
    if group.tag != 1 {
      return group
    }
    @lib.Group::operation(
      group.attributes.map(original => {
        if original.name == attribute.name {
          attribute
        } else {
          original
        }
      }),
    )
  })
  @lib.Message::{ ..request, groups, }
}

///|
test "printer-uri must be one URI value" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").printer_attributes(
    1,
  )
  for
    attribute in [
      @lib.Attribute::new(
        "printer-uri",
        @lib.Keyword("ipp://localhost/ipp/print"),
      ),
      @lib.Attribute::{
        name: "printer-uri",
        values: [
          @lib.Uri("ipp://localhost/ipp/print"),
          @lib.Uri("ipp://other/ipp/print"),
        ],
      },
    ] {
    try
      @lib.validate_request(replace_operation_value(request, attribute))
    catch {
      _ => ()
    } noraise {
      _ => fail("ambiguous printer URI accepted")
    }
  }
}

///|
test "job identity must be one positive integer" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").job_attributes(
    1, 27,
  )
  for
    attribute in [
      @lib.Attribute::new("job-id", @lib.Enumeration(27)),
      @lib.Attribute::{
        name: "job-id",
        values: [@lib.Integer(27), @lib.Integer(28)],
      },
    ] {
    try
      @lib.validate_request(replace_operation_value(request, attribute))
    catch {
      _ => ()
    } noraise {
      _ => fail("ambiguous job identity accepted")
    }
  }
}

///|
test "document format and last-document do not accept multiple values" {
  let request = @lib.RequestContext::new("ipp://localhost/ipp/print").send_document(
    1, 27, "application/pdf", b"pdf",
  )
  for
    attribute in [
      @lib.Attribute::{
        name: "document-format",
        values: [@lib.MimeType("application/pdf"), @lib.MimeType("image/jpeg")],
      },
      @lib.Attribute::{
        name: "last-document",
        values: [@lib.Boolean(true), @lib.Boolean(false)],
      },
    ] {
    try
      @lib.validate_request(replace_operation_value(request, attribute))
    catch {
      _ => ()
    } noraise {
      _ => fail("ambiguous document metadata accepted")
    }
  }
}
