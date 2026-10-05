///|
pub(all) enum ChangeKind {
  Added
  Removed
  Changed
} derive(Eq, Debug)

///|
pub extend ChangeKind with Eq::{equal, not_equal}

///|
pub extend ChangeKind with @debug.Debug::{to_repr}

///|
pub(all) struct CapabilityChange {
  attribute : String
  kind : ChangeKind
  before : Array[IppValue]
  after : Array[IppValue]
  transient : Bool
} derive(Eq, Debug)

///|
pub extend CapabilityChange with Eq::{equal, not_equal}

///|
pub extend CapabilityChange with @debug.Debug::{to_repr}

///|
pub fn volatile_printer_attribute(name : String) -> Bool {
  match name {
    "printer-up-time"
    | "printer-current-time"
    | "printer-state"
    | "printer-state-reasons"
    | "printer-state-message"
    | "queued-job-count"
    | "printer-state-change-time"
    | "printer-state-change-date-time"
    | "printer-config-change-time"
    | "printer-config-change-date-time"
    | "printer-is-accepting-jobs" => true
    _ => false
  }
}

///| Multi-valued supported attributes are treated as multisets, not sequences.

///|
/// Duplicate values remain significant. Collection member order is retained.
fn same_values(left : Array[IppValue], right : Array[IppValue]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let used = FixedArray::make(right.length(), false)
  for value in left {
    let mut found = false
    for index, candidate in right {
      if !used[index] && candidate == value {
        used[index] = true
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
pub fn compare_capabilities(
  before : Capabilities,
  after : Capabilities,
  include_volatile? : Bool = false,
) -> Array[CapabilityChange] {
  let changes : Array[CapabilityChange] = []
  let seen : Map[String, Bool] = Map([])
  for attribute in before.printer.attributes {
    seen[attribute.name] = true
    let transient = volatile_printer_attribute(attribute.name)
    if transient && !include_volatile {
      continue
    }
    match after.printer.find(attribute.name) {
      None =>
        changes.push({
          attribute: attribute.name,
          kind: Removed,
          before: attribute.values,
          after: [],
          transient,
        })
      Some(next) =>
        if !same_values(attribute.values, next.values) {
          changes.push({
            attribute: attribute.name,
            kind: Changed,
            before: attribute.values,
            after: next.values,
            transient,
          })
        }
    }
  }
  for attribute in after.printer.attributes {
    if seen.contains(attribute.name) {
      continue
    }
    let transient = volatile_printer_attribute(attribute.name)
    if transient && !include_volatile {
      continue
    }
    changes.push({
      attribute: attribute.name,
      kind: Added,
      before: [],
      after: attribute.values,
      transient,
    })
  }
  changes.sort_by(fn(left, right) { left.attribute.compare(right.attribute) })
  changes
}

///|
pub fn CapabilityChange::to_json(self : CapabilityChange) -> Json {
  {
    "attribute": Json::string(self.attribute),
    "kind": Json::string(
      match self.kind {
        Added => "added"
        Removed => "removed"
        Changed => "changed"
      },
    ),
    "before": Json::array(self.before.map(value => value.to_json())),
    "after": Json::array(self.after.map(value => value.to_json())),
    "transient": Json::boolean(self.transient),
  }
}
