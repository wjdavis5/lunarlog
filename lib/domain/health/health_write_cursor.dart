/// The health write path's forward-only cursor, as it is stored (Issue
/// #1577).
///
/// The cursor is the `updatedAt` of the newest row the write pass has
/// written; a row is written when its `updatedAt` is after it. A row's
/// `updatedAt` carries microseconds. The cursor used to be stored in whole
/// milliseconds only, so the newest row written was still after it, by its
/// microseconds, and was written to the health store again on every pass.
///
/// It is now stored twice: in milliseconds, under the key it always had,
/// and in microseconds beside it. The millisecond value stays the one that
/// decides which instant is meant. The microsecond value refines it, and
/// counts only while the two agree, so anything that writes the old key
/// alone (an earlier build, a write cut short between the two keys) is
/// read as it always was: the start of that millisecond. That reading can
/// only write a row again; it can never skip one.
library;

/// The cursor instant for its two stored forms. [microseconds] is used
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
