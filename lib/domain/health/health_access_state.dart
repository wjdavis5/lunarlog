/// What the Health sync screen's status line says about lunarlog's access
/// to this device's health store (Issue #1515), decided here as a pure
/// function of the two OS-permission answers so every case runs under a
/// plain unit test.
///
/// Until #1515 the line was the write answer alone
/// ([HealthPermissionProbe.permissionStatus]). On Android that told someone
/// who had let lunarlog read from Health Connect and not write to it that
/// her access was "denied", while her import — by tap and in the background
/// — was working. Since Issue #1491 there is a read-side answer too
/// ([HealthPermissionProbe.importPermissionStatus]), so the line can say
/// what is true: reading is on and writing is off.
///
/// **The read side is only ever believed where the store discloses it.**
/// HealthKit never tells an app whether it may read, so on an iPhone the
/// "read-side answer" is the write answer under another name. The caller
/// therefore passes `read: null` wherever
/// [HealthPermissionProbe.readAccessDisclosed] is false, and with a null
/// read answer this function can only return what the write answer says —
/// [HealthAccessState.readingOnly], [HealthAccessState.writingOnly] and
/// [HealthAccessState.writingSomeOnly] are unreachable. That is how an
/// iPhone is kept out of the states that speak of reading: by the platform
/// fact, never by comparing the two answers.
///
/// **Some write types on and some off is its own state (Issue #1555).**
/// Both stores let each write type be allowed or declined on its own, and
/// the write pass writes the ones that are on. The line used to say
/// "denied" for that, beside a list in the store that showed most of the
/// switches on.
library;

import 'health_platform.dart';

/// The state the Health sync screen's status line shows.
enum HealthAccessState {
  /// Every write type is allowed, and reading is not known to be off.
  granted,

  /// Nothing has been answered yet for the writes, and reading is not on.
  notAsked,

  /// Writing was asked for and no write type is allowed, and reading is
  /// not on.
  denied,

  /// There is no health store, or its permission surface cannot answer.
  unavailable,

  /// Reading is allowed and writing is not: the import works, by tap and
  /// in the background, and nothing is written. Only where the store
  /// discloses read access (Health Connect).
  readingOnly,

  /// Every write type is allowed and reading is not: logged days are
  /// written, and the import cannot read. Only where the store discloses
  /// read access.
  writingOnly,

  /// Some write types are allowed and some are not, and reading is not
  /// known to be off (Issue #1555): the types that are on are written, the
  /// others are left out. On either platform.
  writingSome,

  /// Some write types are allowed and some are not, and reading is off:
  /// [writingSome], and the import cannot read. Only where the store
  /// discloses read access.
  writingSomeOnly;

  /// Whether the way to change this state is the platform's own settings
  /// screen, so the status line says so and the screen offers the link.
  bool get changedInSettings => switch (this) {
        denied ||
        readingOnly ||
        writingOnly ||
        writingSome ||
        writingSomeOnly =>
          true,
        granted || notAsked || unavailable => false,
      };
}

/// The status line's state for the write-side answer [write] and the
/// read-side answer [read].
///
/// [read] is null wherever the store does not disclose read access — see
/// the library doc. With a null [read], or one that cannot tell
/// ([HealthPermissionStatus.unavailable]), the result is exactly what the
/// line said before Issue #1515: [write] on its own.
HealthAccessState healthAccessState({
  required HealthPermissionStatus write,
  required HealthPermissionStatus? read,
}) {
  if (read == HealthPermissionStatus.granted && _knownOff(write)) {
    return HealthAccessState.readingOnly;
  }
  if (write == HealthPermissionStatus.granted && _knownOff(read)) {
    return HealthAccessState.writingOnly;
  }
  if (write == HealthPermissionStatus.partial && _knownOff(read)) {
    return HealthAccessState.writingSomeOnly;
  }
  return _writeAlone(write);
}

/// Whether [status] is a definite "not allowed": asked and declined, or not
/// yet asked. `unavailable` is "cannot tell" and null is "not disclosed";
/// neither is a known no.
bool _knownOff(HealthPermissionStatus? status) =>
    status == HealthPermissionStatus.denied ||
    status == HealthPermissionStatus.notAsked;

HealthAccessState _writeAlone(HealthPermissionStatus write) => switch (write) {
      HealthPermissionStatus.granted => HealthAccessState.granted,
      HealthPermissionStatus.partial => HealthAccessState.writingSome,
      HealthPermissionStatus.notAsked => HealthAccessState.notAsked,
      HealthPermissionStatus.denied => HealthAccessState.denied,
      HealthPermissionStatus.unavailable => HealthAccessState.unavailable,
    };
