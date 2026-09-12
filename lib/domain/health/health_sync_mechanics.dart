/// Health-store sync mechanics (Issue #186): the device-local anchor
/// controller, the own-write loop-breaker, and the change classification
/// that #217/#228's import/export flows consume. This file is the
/// mechanics, not the flows — it owns how an anchor is read, advanced, and
/// cleared (the `ChangesTokenExpiredException` fallback), how a change is
/// filtered so a write→observe→import→write echo is impossible, and how
/// deletions are treated (a no-op for v1). The actual read/import/export
/// feature flows (#217/#228) call these primitives.
///
/// ## Loop-breaking (the infinite-echo prevention)
///
/// Enabling both the write and read directions creates an echo unless
/// own-written samples are excluded on import. The primary loop-breaker is
/// the *source* filter: a Health Connect change carries `dataOrigin` (the
/// writing package) and a HealthKit sample carries `HKSource` (the writing
/// app) — anything whose origin is lunarlog's own package/app is the echo
/// of our own write and must never be re-imported. The secondary/backup
/// loop-breaker is the external id: HealthKit samples we wrote carry
/// `HKMetadataKeyExternalUUID` = the lunarlog record id, and Health Connect
/// records we wrote carry `clientRecordId` = the lunarlog record id, so even
/// a change whose origin is unreadable can be recognised by its external id
/// (`day_entry_id` of the record we exported). A change is an own-write when
/// either signal says so.
///
/// ## Deletions (v1 assumption, issue #186)
///
/// A Health Connect deletion change is a **no-op** on import for v1 — it is
/// not propagated as a lunarlog tombstone, matching the issue's stated
/// recommendation (Clue's own Apple Health integration does not document
/// delete propagation either). It is counted in the run report so the
/// decision stays observable and can be revisited with real usage data.
///
/// Pure Dart (R14/R16): the `HealthStoreChangeSource` is a domain port whose
/// platform-backed implementation (#217/#228) will be wired in the data
/// layer; the controller here is the whole anchor policy and runs under
/// `flutter test` against injected fakes.
library;

// The controller takes its collaborators as constructor parameters that are
// not initializing formals (private finals via the initializer list), the
// same declared pattern the write service and publishers use.
// ignore_for_file: prefer_initializing_formals

import 'health_sync_state_repository.dart';

/// Raised by a [HealthStoreChangeSource] when the stored change token has
/// expired. Health Connect tokens expire after 30 days; a household that
/// leaves the app alone for a month will hit this on its next foreground
/// sync. The anchor controller catches it and falls back to a full
/// time-range read (clearing the stored anchor) instead of letting it
/// surface as an unhandled error.
class ChangesTokenExpiredException implements Exception {
  const ChangesTokenExpiredException([this.message]);

  final String? message;

  @override
  String toString() =>
      'ChangesTokenExpiredException: $message'.trimRight();
}

/// One change record the platform surfaced since an anchor.
class HealthStoreChange {
  const HealthStoreChange({
    required this.externalId,
    this.dataOrigin,
    this.isDeletion = false,
  });

  /// The foreign system's id for the underlying sample/record: HealthKit's
  /// `HKMetadataKeyExternalUUID` (or the store-assigned UUID when absent),
  /// Health Connect's `clientRecordId`. For a change we wrote ourselves this
  /// equals the lunarlog record id (a `day_entry_id` ULID) — the backup
  /// loop-breaker.
  final String externalId;

  /// Health Connect's `dataOrigin` (the writing package) or HealthKit's
  /// `HKSource` bundle identifier. Null when the platform did not surface
  /// it (e.g. HealthKit `HKSource` is not available on this sample type).
  final String? dataOrigin;

  /// True when this change is a Health Connect deletion (the record was
  /// removed from the store). Treated as a no-op on import for v1.
  final bool isDeletion;
}

/// What one [HealthStoreChangeSource] call returned: the advance token the
/// caller should persist as the next anchor, plus the changes since the
/// previous anchor.
class HealthStoreChanges {
  const HealthStoreChanges({
    required this.newAnchor,
    required this.changes,
  });

  /// The platform's next opaque change token / anchor, or null when the
  /// source could not produce one (the full time-range read's terminal
  /// anchor). Persisted verbatim as the next `health_sync_state.anchor`.
  final String? newAnchor;

  /// The changes since the previous anchor, in no particular order.
  final List<HealthStoreChange> changes;
}

/// The platform-backed read source (#217/#228 will provide the method
/// channel implementation; this file is the pure contract the anchor
/// controller depends on).
abstract interface class HealthStoreChangeSource {
  /// Returns changes since [anchor]. When [anchor] is null (no stored
  /// anchor, or the previous one expired) the source performs a full
  /// time-range read. Throws [ChangesTokenExpiredException] when [anchor]
  /// is non-null but the platform reports it expired.
  Future<HealthStoreChanges> getChanges({String? anchor});
}

/// Decides whether a [HealthStoreChange] is lunarlog's own write and must
/// be excluded from import. Primary signal: the change's [dataOrigin]
/// (Health Connect `dataOrigin` / HealthKit `HKSource`) equals our own
/// package/app; backup signal: the change's [externalId] is one of the
/// record ids this device exported ([HealthGuardFacts]-scoped, supplied by
/// the caller from what it wrote).
///
/// Pure, so it is unit-tested in isolation (AC5).
class HealthOwnSourceFilter {
  const HealthOwnSourceFilter();

  /// Whether [change] originated from lunarlog's own store write.
  ///
  /// [ownDataOrigin] is the device's own package name (Android) / bundle
  /// identifier (iOS) — passed in, never read from the environment, so this
  /// stays a pure function. [ownExternalIds] is the set of lunarlog record
  /// ids this device has written to the store (the backup loop-breaker);
  /// when empty it contributes nothing (the origin signal alone decides).
  bool isOwnWrite(
    HealthStoreChange change, {
    required String ownDataOrigin,
    required Set<String> ownExternalIds,
  }) {
    if (change.dataOrigin != null && change.dataOrigin == ownDataOrigin) {
      return true;
    }
    if (ownExternalIds.contains(change.externalId)) return true;
    return false;
  }

  /// Whether [change] should be imported: not an own-write (loop-breaker)
  /// and not a deletion (v1 no-op assumption). Counting a filtered change is
  /// the caller's job, so the report stays observable.
  bool shouldImport(
    HealthStoreChange change, {
    required String ownDataOrigin,
    required Set<String> ownExternalIds,
  }) {
    if (isOwnWrite(change,
        ownDataOrigin: ownDataOrigin, ownExternalIds: ownExternalIds)) {
      return false;
    }
    return !change.isDeletion;
  }
}

/// The outcome of one [HealthSyncAnchorController.syncForPlatform] run —
/// every decision made, so a future import flow can log or surface it
/// without re-deriving it. Counts only; no health content ever leaves the
/// device (R18).
class HealthSyncRunReport {
  const HealthSyncRunReport({
    required this.platform,
    required this.hadAnchor,
    required this.fellBackToFullRead,
    required this.ownWritesSkipped,
    required this.deletionsSkipped,
    required this.importsEligible,
    required this.advancedAnchor,
  });

  final String platform;

  /// Whether a stored anchor existed before this run.
  final bool hadAnchor;

  /// True when the run hit a [ChangesTokenExpiredException] and fell back to
  /// a full time-range read (clearing the stored anchor).
  final bool fellBackToFullRead;

  /// Changes filtered out as our own writes (the loop-breaker).
  final int ownWritesSkipped;

  /// Deletion changes skipped (the v1 no-op assumption).
  final int deletionsSkipped;

  /// Changes eligible for import (not own-writes, not deletions) — the list
  /// #217/#228's import flow consumes.
  final int importsEligible;

  /// True when the run produced a new anchor and persisted it.
  final bool advancedAnchor;
}

/// The anchor policy: read the stored anchor, fetch changes (falling back to
/// a full time-range read on [ChangesTokenExpiredException]), filter
/// own-writes, treat deletions as no-ops, and advance the anchor. This is
/// the *mechanics* — it never imports or writes health content itself, so it
/// stays independent of the #217/#228 flows that will call it.
class HealthSyncAnchorController {
  HealthSyncAnchorController({
    required HealthSyncStateRepository anchors,
    required HealthStoreChangeSource source,
    required HealthOwnSourceFilter filter,
    required String ownDataOrigin,
    required Set<String> Function() ownExternalIds,
    DateTime Function()? now,
  })  : _anchors = anchors,
        _source = source,
        _filter = filter,
        _ownDataOrigin = ownDataOrigin,
        _ownExternalIds = ownExternalIds,
        _now = now ?? (() => DateTime.now().toUtc());

  final HealthSyncStateRepository _anchors;
  final HealthStoreChangeSource _source;
  final HealthOwnSourceFilter _filter;
  final String _ownDataOrigin;
  final Set<String> Function() _ownExternalIds;
  final DateTime Function() _now;

  /// Runs one anchor-managed change fetch for [platform].
  Future<HealthSyncRunReport> syncForPlatform(String platform) async {
    final stored = await _anchors.readAnchor(platform);
    final hadAnchor = stored?.anchor != null;

    HealthStoreChanges changes;
    var fellBack = false;
    try {
      changes = await _source.getChanges(anchor: stored?.anchor);
    } on ChangesTokenExpiredException {
      // 30-day token expiry: clear the anchor so the next read is a full
      // time-range read, then retry once. This WILL fire for a household
      // that leaves the app alone for a month — it must never surface as an
      // unhandled error.
      await _anchors.writeAnchor(HealthSyncAnchor(
        platform: platform,
        anchor: null,
        lastSyncedAt: _now(),
      ));
      fellBack = true;
      changes = await _source.getChanges(anchor: null);
    }

    final ownExternalIds = _ownExternalIds();
    var ownWrites = 0;
    var deletions = 0;
    var imports = 0;
    for (final change in changes.changes) {
      final eligible = _filter.shouldImport(
        change,
        ownDataOrigin: _ownDataOrigin,
        ownExternalIds: ownExternalIds,
      );
      if (!eligible) {
        if (_filter.isOwnWrite(
          change,
          ownDataOrigin: _ownDataOrigin,
          ownExternalIds: ownExternalIds,
        )) {
          ownWrites++;
        } else {
          deletions++;
        }
        continue;
      }
      imports++;
    }

    // Advance the anchor to whatever the source returned (a full time-range
    // read returns a fresh token too). Only on success — a throwing call
    // leaves the old anchor (or, after the fallback, the cleared anchor) for
    // the next run to retry.
    var advanced = false;
    if (changes.newAnchor != null) {
      await _anchors.writeAnchor(HealthSyncAnchor(
        platform: platform,
        anchor: changes.newAnchor,
        lastSyncedAt: _now(),
      ));
      advanced = true;
    }

    return HealthSyncRunReport(
      platform: platform,
      hadAnchor: hadAnchor,
      fellBackToFullRead: fellBack,
      ownWritesSkipped: ownWrites,
      deletionsSkipped: deletions,
      importsEligible: imports,
      advancedAnchor: advanced,
    );
  }
}
