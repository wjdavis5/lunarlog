/// What the health write pass keeps from one pass to the next, beside the
/// forward-only floor and the export ledger (Issue #1581).
///
/// The ledger says what is in the health store. Two things it cannot say
/// are kept here, in one device-local settings value
/// (`SettingsKeys.healthSyncWriteState`) that is cleared with the binding.
/// Neither is health content: type names and times only.
///
/// * **A floor for each write type.** Write access is given type by type.
///   A record of a type that was switched off when its row was saved is
///   not sent when the type is switched on later: forward-only holds for
///   each type, not only for the first grant. So every pass that finds a
///   type off moves that type's floor to the present (never back), and a
///   record that has never been written is sent only when its row is
///   newer than its type's floor. A pass that finds write access removed
///   altogether moves every type's floor. (A record the ledger already
///   holds is another matter:
///   it is in the store, and a correction to it is sent whenever its type
///   allows.)
///
///   Issue #1604: the pass also remembers which types it found off
///   ([typesOff]). The next pass that finds one of them switched on again
///   moves its floor to the present too — that is the moment it came back,
///   as near as this device can see — so a row that arrived while the type
///   was off but after the last pass that looked (a row synced in from
///   another device while the app was closed, or one saved in the moment
///   before the app was left) is not sent when the type returns. Before
///   that, only a pass that found the type off moved its floor, and such a
///   row fell between the last such pass and the one that found it on.
/// * **How far no-flow days have been cleared.** A day with no flow should
///   have no flow record in the store. The ledger says when one was
///   written by this binding, but not when an earlier binding or an
///   earlier install wrote one, so a day saved with no flow is also asked
///   to be deleted once, blind, the way it always was. This is the time of
///   the newest such day already asked for, so it is asked once and not on
///   every pass.
///
/// Its presence is also how a pass knows the ledger is in this build's
/// form: a binding with no value yet was last run by a build that stamped
/// ledger rows with the time of the export.
///
/// Pure Dart (R14/R16).
library;

import 'dart:convert';

class HealthWritePassState {
  const HealthWritePassState({
    this.typeFloors = const {},
    this.typesOff = const {},
    this.clearedThrough,
  });

  /// The floor of each write type that has been found switched off, by the
  /// name `HealthPlatformStore.grantedWriteTypes` gives it.
  final Map<String, DateTime> typeFloors;

  /// The write types the last pass that looked found switched off, by the
  /// same names. A type in here that the next pass finds on has its floor
  /// moved to that pass's present ([withObservedTypesOff]): the moment it
  /// came back, as near as this device can see, so what arrived while it
  /// was off stays out (Issue #1604).
  final Set<String> typesOff;

  /// The `updatedAt` of the newest no-flow day whose flow record has been
  /// asked to be deleted without the ledger knowing of one.
  final DateTime? clearedThrough;

  /// Whether a record of [type] that has never been written may be sent
  /// for a row at [version]: the type has never been found off, or the row
  /// was saved after it last was.
  bool admitsNew(String type, DateTime version) {
    final floor = typeFloors[type];
    return floor == null || version.isAfter(floor);
  }

  /// Whether a no-flow day at [version] has yet to be asked for.
  bool notYetCleared(DateTime version) {
    final through = clearedThrough;
    return through == null || version.isAfter(through);
  }

  /// This state after a pass has looked at which write types are switched
  /// off (Issue #1604): [offNow] becomes [typesOff], and the floor of every
  /// type in [offNow] — just found off — and of every type that was off at
  /// the last look and is not now — just found switched on again — moves to
  /// [at]. A floor is never moved back: [at] is read from a clock that can
  /// be corrected backwards, and a row already kept out must stay out.
  HealthWritePassState withObservedTypesOff(
    Iterable<String> offNow,
    DateTime at,
  ) {
    final now = offNow.toSet();
    final moved = {...typeFloors};
    for (final type in {...now, ...typesOff}) {
      final floor = moved[type];
      if (floor == null || at.isAfter(floor)) moved[type] = at;
    }
    return HealthWritePassState(
      typeFloors: moved,
      typesOff: now,
      clearedThrough: clearedThrough,
    );
  }

  /// This state with no-flow days cleared through [version], never moved
  /// back.
  HealthWritePassState withClearedThrough(DateTime version) =>
      HealthWritePassState(
        typeFloors: typeFloors,
        typesOff: typesOff,
        clearedThrough: notYetCleared(version) ? version : clearedThrough,
      );

  /// The stored form: times in epoch microseconds, the precision a row's
  /// `updatedAt` has. The off-type names are sorted so the encoding is
  /// stable — [_closeState] compares it to what was stored to decide
  /// whether to write at all.
  String encode() => jsonEncode({
        'typeFloors': {
          for (final floor in typeFloors.entries)
            floor.key: floor.value.microsecondsSinceEpoch,
        },
        if (typesOff.isNotEmpty) 'typesOff': (typesOff.toList()..sort()),
        if (clearedThrough != null)
          'clearedThroughUs': clearedThrough!.microsecondsSinceEpoch,
      });

  /// Reads the stored form. Null when there is nothing stored, or what is
  /// stored cannot be read: the caller then starts from an empty state and
  /// brings the ledger into this build's form again, which is safe to do
  /// twice.
  static HealthWritePassState? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final floors = json['typeFloors'];
      final off = json['typesOff'];
      final cleared = json['clearedThroughUs'];
      return HealthWritePassState(
        typeFloors: {
          if (floors is Map)
            for (final floor in floors.entries)
              if (floor.key is String && floor.value is int)
                floor.key as String: _instant(floor.value as int),
        },
        // A state stored before Issue #1604 carries no set: the last pass
        // that looked is unknown, so nothing is treated as re-enabled
        // until this build's first pass records one.
        typesOff: {
          if (off is List)
            for (final type in off)
              if (type is String) type,
        },
        clearedThrough: cleared is int ? _instant(cleared) : null,
      );
    } on FormatException {
      return null;
    }
  }

  static DateTime _instant(int microseconds) =>
      DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
}
