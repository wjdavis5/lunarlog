/// The device-local computed-cycle-deviation insight service (Issue #799,
/// deferred from #217) — the effectful half behind the overview's
/// "Apple Health noticed…" card.
///
/// It is deliberately **separate** from [LocalHealthImportService]: the
/// flow-import merge pipeline is untouched by this feature, and this
/// service only ever *reads* Apple's four computed deviation types and
/// persists a display snapshot. It is also **read-only, permanently**:
/// Apple derives these values from the user's own Health data, and App
/// Review 5.1.3 forbids writing derived data back. The port it reads
/// ([HealthImportSource.readCycleDeviations]) has no write counterpart, and
/// the write port has no method that accepts a [HealthDeviationKind].
///
/// **What it does, in order (all best-effort — this never fails the import
/// pass it is appended to):**
///
/// 1. Resolves the profile bound to this device's health store and the same
///    guard facts every write evaluates. No bound profile, or a denied
///    guard, ends with an empty snapshot touching no health API.
/// 2. Reads the four deviation types over a bounded
///    [kHealthDeviationWindowDays] window.
/// 3. Resolves each deviation interval's civil start/end from the sample's
///    own zone (Apple's computed samples carry none, so the read forwards
///    this phone's offset, flagged) and keeps at most one per kind — the
///    most recent.
/// 4. Persists the snapshot device-locally ([SettingsStore]), never synced:
///    it is a display of Apple's own computation on this phone, not a fact
///    about the profile.
///
/// Pure Dart (R14/R16): every collaborator is an injected interface and
/// time/"today" are injectable, so all branches run under `flutter test`.
library;

import 'package:lunarlog/domain/health/day_boundary.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart'
    show GuardiansForProfile;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/util/timezone.dart' show fixedOffsetZoneName;

// The private finals via the initializer list, the same declared pattern
// `health_import_service.dart` uses.
// ignore_for_file: prefer_initializing_formals

/// The concrete [HealthDeviationInsights]. Every expected failure mode
/// becomes an empty snapshot; only an unexpected settings-storage error
/// propagates, matching the import service's contract.
class LocalHealthDeviationService implements HealthDeviationInsights {
  LocalHealthDeviationService({
    required HealthImportSource source,
    required HealthSyncBinding binding,
    required bool minorBindingAllowed,
    required ProfilesRepository profiles,
    required GuardiansForProfile guardiansForProfile,
    required String? Function() signedInUserId,
    required SettingsStore settings,
    LocalDate Function()? today,
    DateTime Function()? now,
  }) : _source = source,
       _binding = binding,
       _minorBindingAllowed = minorBindingAllowed,
       _profiles = profiles,
       _guardiansForProfile = guardiansForProfile,
       _signedInUserId = signedInUserId,
       _settings = settings,
       _today = today ?? LocalDate.today,
       _now = now ?? (() => DateTime.now().toUtc());

  final HealthImportSource _source;
  final HealthSyncBinding _binding;
  final bool _minorBindingAllowed;
  final ProfilesRepository _profiles;
  final GuardiansForProfile _guardiansForProfile;
  final String? Function() _signedInUserId;
  final SettingsStore _settings;
  final LocalDate Function() _today;
  final DateTime Function() _now;

  @override
  Future<HealthDeviationSnapshot?> visibleSnapshot(String profileId) async {
    // The import gate: a snapshot only exists because a read was allowed for
    // the profile then bound to this device. If the binding has moved (or
    // was cleared), this profile's snapshot must not surface.
    if (await _binding.boundProfileId() != profileId) return null;
    final snapshot = decodeHealthDeviationSnapshot(
      await _settings.get(healthDeviationSnapshotSettingKey(profileId)),
    );
    if (snapshot.isEmpty) return null;
    final dismissed = await _settings.get(
      healthDeviationDismissedSettingKey(profileId),
    );
    if (dismissed == snapshot.fingerprint) return null;
    return snapshot;
  }

  @override
  Future<void> dismiss(
    String profileId,
    HealthDeviationSnapshot snapshot,
  ) =>
      _settings.set(
        healthDeviationDismissedSettingKey(profileId),
        snapshot.fingerprint,
      );

  @override
  Future<HealthDeviationSnapshot> refresh() async {
    final bound = await _resolveBound();
    if (bound == null) return const HealthDeviationSnapshot();

    final check = await _binding.canWrite(
      profile: bound.profile,
      signedInUserId: bound.facts.signedInUserId,
      ownerUserId: bound.facts.ownerUserId,
      minorBindingAllowed: _minorBindingAllowed,
    );
    if (!check.isAllowed) return const HealthDeviationSnapshot();

    final window = _window();
    final read = await _source.readCycleDeviations(
      bound.facts,
      start: window.queryStart,
      end: window.queryEnd,
    );
    final snapshot = _snapshotFrom(read);
    await _settings.set(
      healthDeviationSnapshotSettingKey(bound.profile.id),
      encodeHealthDeviationSnapshot(snapshot),
    );
    return snapshot;
  }

  /// The bound profile plus its guard facts, or null when health sync is off
  /// for this device or the bound profile no longer resolves.
  Future<({Profile profile, HealthGuardFacts facts})?> _resolveBound() async {
    final profileId = await _binding.boundProfileId();
    if (profileId == null) return null;
    final profile = await _profiles.findById(profileId);
    if (profile == null) return null;
    final facts = HealthGuardFacts(
      profile: profile,
      signedInUserId: _signedInUserId(),
      ownerUserId: ownerUserIdFor(await _guardiansForProfile(profileId)),
    );
    return (profile: profile, facts: facts);
  }

  /// The bounded query window: [kHealthDeviationWindowDays] civil days back
  /// through tomorrow, widened a day either side, resolved as zone-free UTC
  /// instants exactly like the flow import's window.
  ({DateTime queryStart, DateTime queryEnd}) _window() {
    final to = _today();
    final from = to.addDays(-kHealthDeviationWindowDays);
    return (
      queryStart: DateTime.utc(
        from.year,
        from.month,
        from.day,
      ).subtract(const Duration(days: 1)),
      queryEnd: DateTime.utc(
        to.year,
        to.month,
        to.day,
      ).add(const Duration(days: 2)),
    );
  }

  /// Maps one read result to a snapshot: a non-sample outcome is an empty
  /// snapshot, and samples are deduped to the most recent per kind.
  HealthDeviationSnapshot _snapshotFrom(HealthDeviationReadResult read) {
    if (read is! HealthDeviationSamples) {
      return const HealthDeviationSnapshot();
    }
    final byKind = <HealthDeviationKind, HealthDeviationInsight>{};
    for (final sample in read.samples) {
      final start = _civilDate(sample, sample.start);
      if (start == null) continue;
      final end = _civilDate(sample, sample.end) ?? start;
      final insight = HealthDeviationInsight(
        kind: sample.kind,
        start: start,
        end: end,
        recordId: sample.recordId,
        tz: _zoneLabel(sample),
      );
      final current = byKind[sample.kind];
      if (current == null || start.isAfter(current.start)) {
        byKind[sample.kind] = insight;
      }
    }
    final insights = byKind.values.toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    return HealthDeviationSnapshot(insights: insights, observedAt: _now());
  }

  /// The civil date [instant] resolves to via the sample's own zone (IANA
  /// name, or a raw offset), or null when the sample carries neither.
  LocalDate? _civilDate(HealthDeviationSample sample, DateTime instant) {
    final tzName = sample.tzName;
    if (tzName != null && tzName.isNotEmpty) {
      try {
        return localDateForSample(instant, tzName: tzName);
      } on TimeZoneResolutionException {
        return null;
      }
    }
    final offset = sample.offset;
    if (offset == null) return null;
    return localDateForSample(instant, offset: offset);
  }

  /// The diagnostic zone label stored with an insight — never rendered.
  String _zoneLabel(HealthDeviationSample sample) {
    final tzName = sample.tzName;
    if (tzName != null && tzName.isNotEmpty) return tzName;
    final offset = sample.offset;
    if (offset == null) return '';
    return fixedOffsetZoneName(offset);
  }
}
