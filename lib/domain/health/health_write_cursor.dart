/// The health write path's forward-only floor, as it is stored (Issue
/// #1577).
///
/// The floor is the moment write access was granted; a row is looked at
/// when its `updatedAt` is after it. A row's `updatedAt` carries
/// microseconds, so the floor is kept to the microsecond too. (Until Issue
/// #1581 this value was a cursor that moved to the newest row written. It
/// was stored in whole milliseconds only, so the newest row was still after
/// it, by its microseconds, and went to the health store again on every
/// pass. That is why it is stored the way described here.)
///
/// It is stored twice: in milliseconds, under the key it always had, and in
/// microseconds beside it. The millisecond value stays the one that decides
/// which instant is meant. The microsecond value refines it, and counts
/// only while it names an instant inside that millisecond. When the two
/// name different milliseconds (an earlier build wrote the old key alone,
/// or a write was cut short between the two) the floor is read as it
/// always was: the start of the millisecond. That reading can let through
/// a row saved earlier in the grant's own millisecond; it can never hold
/// back one saved after the grant.
library;

/// The floor's instant for its two stored forms. [microseconds] is used
/// when it names an instant inside [milliseconds]' millisecond.
DateTime healthWriteCursorFrom({
  required int milliseconds,
  required int? microseconds,
}) {
  if (microseconds != null && microseconds ~/ 1000 == milliseconds) {
    return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}
