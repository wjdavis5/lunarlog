/// Apple's computed **cycle deviations** (Issue #799, deferred from #217) —
/// the pure-Dart vocabulary for the four Reproductive Health category types
/// Apple itself derives from the user's logged data.
///
/// **These are read-only, permanently.** Apple computes
/// `irregularMenstrualCycles`, `infrequentMenstrualCycles`,
/// `prolongedMenstrualPeriods`, and `persistentIntermenstrualBleeding` from
/// the user's own Health data; App Store Review guideline 5.1.3 forbids
/// writing derived or inaccurate data into HealthKit. Nothing in this file
/// can write, and the [HealthImportSource] read method that carries them is
/// on the read port only — the write port ([HealthPlatformStore]) has no
/// method that accepts a [HealthDeviationKind], by construction.
///
/// The insight a deviation produces is a **separate, clearly labelled**
/// second opinion, never merged into lunarlog's own prediction
/// (`lib/domain/prediction/prediction.dart`): Apple derives it from
/// whatever the user logged in *Apple Health*, which may differ from what
/// lunarlog holds, so the two can legitimately disagree. This file provides
/// the vocabulary and the device-local snapshot codec; the UI renders the
/// snapshot as its own dismissible line and never feeds it back into the
/// prediction engine.
///
/// Pure Dart (R14/R16): no Flutter/drift imports — this file only composes
/// the platform ports' vocabulary and the persisted snapshot's JSON codec.
library;

import 'dart:convert';

import '../models/local_date.dart';
import 'health_sync_policy.dart' show HealthSyncCheck;

/// One of Apple's four computed cycle-deviation category types.
///
/// [wire] is the closed string both sides of the `lunarlog/health` channel
/// use; [healthKitIdentifier] is the canonical `HKCategoryTypeIdentifier`
/// raw value. The Dart side sends these identifiers as raw values
/// consistently (mirroring #916's symptom-type fix) and the Swift side
/// resolves them through its own `deviationKinds` table — see
/// `AppDelegate.swift` and `test/release/health_deviation_read_types_test.dart`,
/// which pins the two tables together at test time.
enum HealthDeviationKind {
  irregularMenstrualCycles(
    'irregularMenstrualCycles',
    'HKCategoryTypeIdentifierIrregularMenstrualCycles',
  ),
  infrequentMenstrualCycles(
    'infrequentMenstrualCycles',
    'HKCategoryTypeIdentifierInfrequentMenstrualCycles',
  ),
  prolongedMenstrualPeriods(
    'prolongedMenstrualPeriods',
    'HKCategoryTypeIdentifierProlongedMenstrualPeriods',
  ),
  persistentIntermenstrualBleeding(
    'persistentIntermenstrualBleeding',
    'HKCategoryTypeIdentifierPersistentIntermenstrualBleeding',
  );

  const HealthDeviationKind(this.wire, this.healthKitIdentifier);

  /// The wire string on the `lunarlog/health` channel.
  final String wire;

  /// The canonical `HKCategoryTypeIdentifier` raw value (Apple's own SDK
  /// constant name). Never a Swift case name — the read direction passes
  /// raw values consistently so an iOS 15 deployment target can resolve an
  /// iOS 16-only identifier without referencing the enum case.
  final String healthKitIdentifier;

  /// Parses the wire string; null when [raw] is not in the closed set — a
  /// protocol error callers surface, never a silent fallback.
  static HealthDeviationKind? fromWire(String? raw) {
    for (final kind in values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

/// One cycle-deviation sample read from the OS health store, before it is
/// resolved to a lunarlog civil date. [start]/[end] are the interval's own
/// absolute instants; [tzName]/[offset]/[offsetInferred] follow
/// `health_import.dart`'s #180/#902 zone contract exactly (the sample's own
/// IANA zone when HealthKit recorded one, otherwise this phone's offset at
/// the sample's instant for Apple's own computed samples, which carry no
/// `HKMetadataKeyTimeZone`).
class HealthDeviationSample {
  const HealthDeviationSample({
    required this.kind,
    required this.recordId,
    required this.start,
    required this.end,
    this.tzName,
    this.offset,
    this.offsetInferred = false,
  });

  final HealthDeviationKind kind;
  final String recordId;
  final DateTime start;
  final DateTime end;
  final String? tzName;
  final Duration? offset;
  final bool offsetInferred;
}

/// The typed outcome of one deviation read, mirroring `health_import.dart`'s
/// [HealthReadResult] vocabulary. A denied read is deliberately not a
/// distinct state (HealthKit reports it as an empty result, and the UI must
/// never claim to know which happened).
sealed class HealthDeviationReadResult {
  const HealthDeviationReadResult();

  /// The query ran; [samples] is what the store returned (possibly empty).
  const factory HealthDeviationReadResult.samples(
    List<HealthDeviationSample> samples,
  ) = HealthDeviationSamples;

  /// No health store exists on this device.
  const factory HealthDeviationReadResult.unavailable() =
      HealthDeviationUnavailable;

  /// The platform threw a permission error; coalesced with the empty case
  /// by the import service, exactly as the flow read is.
  const factory HealthDeviationReadResult.permissionDenied() =
      HealthDeviationPermissionDenied;

  /// The device-binding guard refused the read; no health API was touched.
  const factory HealthDeviationReadResult.refused(HealthSyncCheck check) =
      HealthDeviationRefused;

  /// A protocol error; [message] is diagnostic, never user-facing.
  const factory HealthDeviationReadResult.failed(String message) =
      HealthDeviationFailed;
}

final class HealthDeviationSamples extends HealthDeviationReadResult {
  const HealthDeviationSamples(this.samples);

  final List<HealthDeviationSample> samples;
}

final class HealthDeviationUnavailable extends HealthDeviationReadResult {
  const HealthDeviationUnavailable();
}

final class HealthDeviationPermissionDenied extends HealthDeviationReadResult {
  const HealthDeviationPermissionDenied();
}

final class HealthDeviationRefused extends HealthDeviationReadResult {
  const HealthDeviationRefused(this.check);

  final HealthSyncCheck check;
}

final class HealthDeviationFailed extends HealthDeviationReadResult {
  const HealthDeviationFailed(this.message);

  final String message;
}

/// One deviation, resolved to civil dates and ready to render.
class HealthDeviationInsight {
  const HealthDeviationInsight({
    required this.kind,
    required this.start,
    required this.end,
    this.recordId = '',
    this.tz = '',
  });

  final HealthDeviationKind kind;

  /// The deviation interval's first civil day.
  final LocalDate start;

  /// The deviation interval's last civil day.
  final LocalDate end;

  /// Diagnostic only; never rendered.
  final String recordId;

  /// Diagnostic only; never rendered.
  final String tz;

  /// A stable identity for this insight, used to decide whether a dismissal
  /// still applies to what is currently stored.
  String get fingerprint => '${kind.wire}|${start.iso}|${end.iso}';

  Map<String, Object?> toJson() => {
        'kind': kind.wire,
        'start': start.iso,
        'end': end.iso,
        if (recordId.isNotEmpty) 'recordId': recordId,
        if (tz.isNotEmpty) 'tz': tz,
      };

  /// Tolerant decode: a malformed item is dropped by the caller rather than
  /// taking a screen down.
  static HealthDeviationInsight? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = HealthDeviationKind.fromWire(raw['kind'] as String?);
    final start = LocalDate.tryParseIso(raw['start'] as String?);
    final end = LocalDate.tryParseIso(raw['end'] as String?);
    if (kind == null || start == null || end == null) return null;
    return HealthDeviationInsight(
      kind: kind,
      start: start,
      end: end,
      recordId: raw['recordId'] as String? ?? '',
      tz: raw['tz'] as String? ?? '',
    );
  }
}

/// What one import pass last read from Apple Health, persisted device-local
/// so the overview can render it without re-reading. Never synced: it is a
/// display of Apple's own computation on this phone's health store, not a
/// fact about the profile.
class HealthDeviationSnapshot {
  const HealthDeviationSnapshot({
    this.insights = const [],
    this.observedAt,
  });

  /// At most one insight per [HealthDeviationKind], most recent first.
  final List<HealthDeviationInsight> insights;

  /// When this snapshot was read, or null for an empty/never snapshot.
  final DateTime? observedAt;

  bool get isEmpty => insights.isEmpty;

  /// A stable identity of the whole snapshot, used by the dismissal latch.
  String get fingerprint =>
      (insights.map((i) => i.fingerprint).toList()..sort()).join('|');

  Map<String, Object?> toJson() => {
        'v': 1,
        if (observedAt != null)
          'observedAt': observedAt!.toUtc().toIso8601String(),
        'insights': [for (final insight in insights) insight.toJson()],
      };
}

/// How far back the deviation read looks. Apple's own cycle-detection
/// algorithm needs several months of history before it will emit a
/// deviation, so a 30-day window would almost never return one; six months
/// is the bounded read the overview insight needs without turning the query
/// into a full-history scan (the #156/A3-16 posture: bounded, never
/// background).
const int kHealthDeviationWindowDays = 180;

/// The device-local insight surface the overview reads (Issue #799). Kept
/// separate from [HealthImportSource] (the raw read port) so the UI depends
/// only on what it renders: a persisted snapshot, a dismissal latch, and an
/// explicit refresh the import flow calls after a pass. Implementations are
/// device-local and never sync.
abstract interface class HealthDeviationInsights {
  /// The snapshot to render for [profileId], or null when there is nothing
  /// to show — no snapshot was ever taken, it is empty, the profile is not
  /// the one currently bound to this device's health store, or the operator
  /// dismissed exactly this snapshot. **This is the import gate**: a
  /// snapshot was only ever written after the binding guard allowed a read,
  /// and requiring `HealthSyncBinding.boundProfileId` to still equal
  /// [profileId] keeps the card off a profile the gate no longer covers.
  Future<HealthDeviationSnapshot?> visibleSnapshot(String profileId);

  /// Records that the operator dismissed [snapshot] on this device. The
  /// same fingerprint stays hidden; a later, different snapshot shows again.
  Future<void> dismiss(String profileId, HealthDeviationSnapshot snapshot);

  /// Reads the currently bound profile's deviations from the OS health
  /// store and persists the result as its snapshot. Best-effort by
  /// contract: a missing binding, a denied guard, or a platform without a
  /// deviation concept yields an empty snapshot rather than an error, so
  /// this never fails an import pass it is appended to. Returns the
  /// snapshot that was persisted.
  Future<HealthDeviationSnapshot> refresh();
}

/// The [SettingsStore] key a profile's deviation snapshot lives under. A
/// device-local display cache, never synced.
String healthDeviationSnapshotSettingKey(String profileId) =>
    'healthDeviationSnapshot.$profileId';

/// The [SettingsStore] key holding the snapshot fingerprint the operator
/// dismissed on this device. A new snapshot with a different fingerprint
/// shows again; the same one stays hidden.
String healthDeviationDismissedSettingKey(String profileId) =>
    'healthDeviationDismissed.$profileId';

/// Serialises [snapshot] as a versioned JSON document. Always succeeds.
String encodeHealthDeviationSnapshot(HealthDeviationSnapshot snapshot) =>
    jsonEncode(snapshot.toJson());

/// Parses a stored snapshot. Unset, empty, or malformed values decode to an
/// empty snapshot (never a throw) — a corrupt cache must not take the
/// overview down, and an empty snapshot simply renders nothing.
HealthDeviationSnapshot decodeHealthDeviationSnapshot(String? raw) {
  if (raw == null || raw.isEmpty) return const HealthDeviationSnapshot();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const HealthDeviationSnapshot();
    final rawInsights = decoded['insights'];
    final insights = <HealthDeviationInsight>[
      if (rawInsights is List)
        for (final item in rawInsights)
          ?HealthDeviationInsight.tryFromJson(item),
    ];
    final observedAtRaw = decoded['observedAt'];
    final observedAt =
        observedAtRaw is String ? DateTime.tryParse(observedAtRaw) : null;
    return HealthDeviationSnapshot(
      insights: insights,
      observedAt: observedAt?.toUtc(),
    );
  } on FormatException {
    return const HealthDeviationSnapshot();
  }
}
