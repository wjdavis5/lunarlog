/// Prediction service: computes [CyclePrediction]s as a map over day-entry
/// repository streams. Nothing is persisted and no write path triggers
/// computation (KTD5) — consumers subscribe, writes re-derive.
///
/// Issue #132: when a [SettingsStore] is injected, the device-local
/// omission list (`omittedCycles.<profileId>`, KTD2) joins the combine —
/// every estimate is re-derived when the operator omits or restores a
/// cycle, and the reminder coordinator and reminder-window publisher
/// (which consume [watch]) replan with it for free.
///
/// Issue #218: when a [ProfilesRepository] is injected, the profile's
/// onboarding cycle facts join the combine too, and a profile that would
/// read [NotEnoughHistory] but carries seedable facts instead gets a
/// [CycleConfidence.provisional] prediction from
/// [seedProvisionalPrediction]. The displacement rule is structural: the
/// computed result is produced first and the facts are consulted *only*
/// when it is [NotEnoughHistory], so once
/// [kMinCompletedValidCycles] real cycles exist the onboarding numbers
/// never blend into the estimate and `provisional` is never returned again
/// for that profile. A null repository (tests, unconfigured wiring) keeps
/// the exact pre-#218 behavior.
///
/// Issue #197 (performance): [watch] intentionally keeps reading the
/// profile's *full* history — predictions need the whole cycle record, not
/// just a displayed window — but memoises [computePredictionFromEntries] on
/// a cheap fingerprint of that history plus the omission set, the facts,
/// and [today] (review follow-up), so a redundant emission carrying the
/// same entries (e.g. `combineLatest2` re-emitting on an exclusions-list
/// tick, or a duplicate/no-op tick from the underlying stream) reuses the
/// previous result instead of re-deriving episodes and cycle stats from
/// scratch.
///
/// Issue #233: a [birthControlStateFor] provider (a `Stream<BirthControlState?>`
/// per profile — the drift `profile_modes` watcher in production) joins the
/// combine, resolved against [today] via `birthControlMethodInEffectOn` into
/// an [ActiveBirthControl] that [computePredictionFromEntries] branches on.
/// The raw state rides the #197 memo key, so a recorded-method change or an
/// effective-window edge (start/stop date crossing today) re-derives, while
/// an unrelated profile-mode row change (e.g. only the mode axis editing)
/// reuses the cached prediction. A null provider keeps the exact pre-#233
/// behavior.
library;

import '../birth_control.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../models/profile.dart';
import '../repositories/day_entries_repository.dart';
import '../repositories/profiles_repository.dart';
import '../repositories/settings_store.dart';
import '../util/combine_latest.dart';
import 'cycle_history.dart';
import 'prediction.dart';

/// A cheap fingerprint of a day-entry list (issue #197, review follow-up):
/// row count plus a single `int` folded in the same `O(n)` pass over
/// `(id, updatedAt.microsecondsSinceEpoch, flow index, deletedAt)` for every
/// row. This replaces an earlier stamp of just `(count, max updatedAt)` —
/// per-row last-write-wins sync applies a *remote* `updatedAt` verbatim
/// (`lib/data/db/storage.dart`), so an incoming synced edit to some row X can
/// carry an `updatedAt` older than the profile's current max, leaving both
/// the count and the max unchanged even though X's flow (or tombstone state)
/// really did change — the count/max stamp would then wrongly reuse a stale
/// cached prediction. Folding every row's own fields into the fingerprint
/// (via a commutative XOR, so row order — never semantically meaningful here
/// — can't itself cause a spurious mismatch) means *any* row's edit changes
/// the fingerprint, not just one that happens to move the maximum.
/// `local_rev` never leaves the storage layer, so it is not part of this
/// fingerprint; folding in `updatedAt` per row is the cheap alternative.
class _EntriesFingerprint {
  const _EntriesFingerprint(this.count, this.folded);

  final int count;

  /// XOR-fold of every row's own hash; see the class doc for why per-row
  /// folding (not just a running max) is required.
  final int folded;

  @override
  bool operator ==(Object other) =>
      other is _EntriesFingerprint &&
      other.count == count &&
      other.folded == folded;

  @override
  int get hashCode => Object.hash(count, folded);
}

/// One row's contribution to [_EntriesFingerprint.folded]: folds
/// `(id, updatedAt.microsecondsSinceEpoch, flow index, deletedAt)` into a
/// single `int` via `Object.hash`, matched against [_fingerprintOf]'s single
/// `O(n)` pass — no per-row list allocation, no second pass.
int _rowFingerprint(DayEntry entry) => Object.hash(
      entry.id,
      entry.updatedAt.microsecondsSinceEpoch,
      entry.flow.index,
      entry.deletedAt?.microsecondsSinceEpoch,
    );

_EntriesFingerprint _fingerprintOf(List<DayEntry> entries) {
  var folded = 0;
  for (final entry in entries) {
    folded ^= _rowFingerprint(entry);
  }
  return _EntriesFingerprint(entries.length, folded);
}

/// Unordered equality for a small omission set (day counts here are never
/// large — see [CycleExclusionList]) without pulling in `package:collection`
/// just for this one comparison.
bool _sameOmissions(Set<LocalDate> a, Set<LocalDate> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  return a.every(b.contains);
}

/// Per-subscription memoisation state for [CyclePredictionService.watch]
/// (issue #197): a fresh instance per `watch()` call, so concurrent
/// subscriptions for different profiles (or the same profile from two
/// widgets) never share a cache. [_today] joins the key (review
/// follow-up) — [CyclePredictionService.watch]'s own doc documents that
/// [LocalDate] is evaluated per emission so a subscription stays correct
/// across midnight; without it in the key, an emission carrying unchanged
/// entries after midnight would wrongly reuse yesterday's cached
/// `daysUntilNextStart`/`cycleDay` instead of re-deriving them against the
/// new `today`. Issue #218 adds the profile's [CycleFacts] to the same
/// key: an emission carrying unchanged entries but a changed facts answer
/// (an onboarding/profile-settings edit) must re-derive, and conversely an
/// unrelated profile-row change (e.g. a rename) that leaves the facts
/// equal must still reuse the cached prediction. Issue #233 adds the raw
/// `profile_modes` birth-control state to the key for the same reason: a
/// recorded-method change, or an effective-window edge (a start/stop date
/// crossing today, which the `birthControlMethodInEffectOn` resolution
/// depends on) must re-derive, while an unrelated mode-row edit reuses the
/// cache. (The record's structural equality is what keeps that honest, and
/// [today] is already in the key, so the effective-window edge against the
/// calendar is covered by the date alone.)
class _PredictionMemo {
  _EntriesFingerprint? _fingerprint;
  Set<LocalDate>? _omissions;
  LocalDate? _today;
  CycleFacts? _facts;
  BirthControlState? _birthControlState;
  CyclePrediction? _prediction;

  /// The cached prediction when [fingerprint]/[omissions]/[today]/[facts]/
  /// [birthControlState] all match the last computed call, or null when a
  /// fresh [computePredictionFromEntries] is needed.
  CyclePrediction? cached(
    _EntriesFingerprint fingerprint,
    Set<LocalDate> omissions,
    LocalDate today,
    CycleFacts facts,
    BirthControlState? birthControlState,
  ) {
    final prediction = _prediction;
    if (prediction == null) return null;
    if (_fingerprint != fingerprint) return null;
    if (_today != today) return null;
    if (!_sameOmissions(_omissions ?? const {}, omissions)) return null;
    if (_facts != facts) return null;
    if (_birthControlState != birthControlState) return null;
    return prediction;
  }

  void store(
    _EntriesFingerprint fingerprint,
    Set<LocalDate> omissions,
    LocalDate today,
    CycleFacts facts,
    BirthControlState? birthControlState,
    CyclePrediction value,
  ) {
    _fingerprint = fingerprint;
    _omissions = omissions;
    _today = today;
    _facts = facts;
    _birthControlState = birthControlState;
    _prediction = value;
  }
}

class CyclePredictionService {
  CyclePredictionService(this._dayEntries,
      {SettingsStore? settings,
      ProfilesRepository? profiles,
      Stream<BirthControlState?> Function(String profileId)?
          birthControlStateFor})
      : _exclusions = settings == null ? null : CycleExclusionList(settings),
        // A named parameter cannot be private, so this direct
        // pass-through cannot be an initializing formal (the same reason
        // the coordinator/publisher files carry file-level ignores).
        // ignore: prefer_initializing_formals
        _profiles = profiles,
        // ignore: prefer_initializing_formals
        _birthControlStateFor = birthControlStateFor;

  final DayEntriesRepository _dayEntries;
  final CycleExclusionList? _exclusions;

  /// Issue #218: the profiles repository supplying each profile's
  /// onboarding cycle facts. Null keeps the exact pre-#218 behavior (no
  /// seeding, no facts in the combine).
  final ProfilesRepository? _profiles;

  /// Issue #233: per-profile `profile_modes` birth-control state watcher
  /// (a `Stream<BirthControlState?>`), resolved against [today] via
  /// `birthControlMethodInEffectOn` into the [ActiveBirthControl] the
  /// predictor branches on. Null keeps the exact pre-#233 behavior (no
  /// birth-control-aware prediction).
  final Stream<BirthControlState?> Function(String profileId)?
      _birthControlStateFor;

  /// Recomputed on every emission of the profile's day-entry stream and,
  /// when a settings store is wired, of the profile's omission-list key —
  /// except when [_PredictionMemo] finds the entries fingerprint, omission
  /// set, facts, and [today] all unchanged from the last computation
  /// (issue #197). [today] is evaluated per emission so long-lived
  /// subscriptions stay correct across midnight; it defaults to the local
  /// civil date.
  Stream<CyclePrediction> watch(String profileId,
      {LocalDate Function()? today}) {
    final todayOf = today ?? LocalDate.today;
    final entries = _dayEntries.watchForProfile(profileId);
    final exclusions = _exclusions;
    final memo = _PredictionMemo();
    // entries + facts + birth-control state (issue #233). When the
    // exclusions store is wired it rides on top of this triple.
    final core = combineLatest3(
      entries,
      _factsFor(profileId),
      _birthControlFor(profileId),
    );
    if (exclusions == null) {
      return core.map(
        (latest) => _predictionFor(
          memo: memo,
          entries: latest.$1,
          omissions: const {},
          today: todayOf(),
          facts: latest.$2,
          birthControlState: latest.$3,
        ),
      );
    }
    return combineLatest2(core, exclusions.watch(profileId)).map(
      (latest) => _predictionFor(
        memo: memo,
        entries: latest.$1.$1,
        omissions: latest.$2,
        today: todayOf(),
        facts: latest.$1.$2,
        birthControlState: latest.$1.$3,
      ),
    );
  }

  /// The profile's raw birth-control state (issue #233), or null when no
  /// [birthControlStateFor] provider is wired. Re-emitted on every
  /// `profile_modes` row change; the record's structural equality keeps the
  /// #197 memo honest about which changes actually matter.
  Stream<BirthControlState?> _birthControlFor(String profileId) {
    final provider = _birthControlStateFor;
    if (provider == null) return Stream.value(null);
    return provider(profileId);
  }

  /// Resolves the raw birth-control state against [today] into the
  /// [ActiveBirthControl] the predictor branches on, via the
  /// `birthControlMethodInEffectOn` seam (issue #260 AC5 — never re-parsed
  /// here). Null when no tracked method is in effect on [today]. A
  /// malformed start date (defensive — the columns are CHECK-bounded
  /// `yyyy-MM-dd`) degrades to null, failing to the no-method path.
  static ActiveBirthControl? _activeBirthControlFor(
    BirthControlState? state,
    LocalDate today,
  ) {
    if (state == null) return null;
    final method = birthControlMethodInEffectOn(
      storedMethod: state.method,
      startedOn: state.startedOn,
      stoppedOn: state.stoppedOn,
      date: today,
    );
    if (method == null) return null;
    return ActiveBirthControl(
      method: method,
      startedOn: _parseStartDate(state.startedOn),
    );
  }

  static LocalDate? _parseStartDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return LocalDate.fromIso(iso);
    } on ArgumentError {
      return null;
    }
  }

  /// The profile's current cycle facts (issue #218), or
  /// [CycleFacts.empty] when no profiles repository is wired or the
  /// profile is not held locally. Re-emitted on every profile-row change;
  /// [CycleFacts]'s value equality is what keeps the #197 memo honest
  /// about which of those changes actually matter.
  Stream<CycleFacts> _factsFor(String profileId) {
    final profiles = _profiles;
    if (profiles == null) return Stream.value(CycleFacts.empty);
    return profiles.watch().map((rows) => _factsOfProfile(
          rows.where((profile) => profile.id == profileId),
        ));
  }

  static CycleFacts _factsOfProfile(Iterable<Profile> profiles) {
    for (final profile in profiles) {
      return CycleFacts(
        lastPeriodStart: profile.lastPeriodStart,
        typicalCycleLengthDays: profile.typicalCycleLengthDays,
        typicalPeriodLengthDays: profile.typicalPeriodLengthDays,
      );
    }
    return CycleFacts.empty;
  }

  CyclePrediction _predictionFor({
    required _PredictionMemo memo,
    required List<DayEntry> entries,
    required Set<LocalDate> omissions,
    required LocalDate today,
    required CycleFacts facts,
    required BirthControlState? birthControlState,
  }) {
    final fingerprint = _fingerprintOf(entries);
    final cached =
        memo.cached(fingerprint, omissions, today, facts, birthControlState);
    if (cached != null) return cached;
    final prediction = _resolve(
      entries: entries,
      omissions: omissions,
      today: today,
      facts: facts,
      birthControlState: birthControlState,
    );
    memo.store(fingerprint, omissions, today, facts, birthControlState,
        prediction);
    return prediction;
  }

  /// Issue #218's resolution order — computed history first, facts only as
  /// the fallback: (1) compute from logged entries exactly as before; (2)
  /// if that is [NotEnoughHistory] and the facts can seed, return the
  /// seeded provisional prediction; (3) otherwise return the computed
  /// result unchanged — including its counts, so an all-skipped onboarding
  /// reads bit-identically to a pre-#218 profile.
  ///
  /// Issue #233: a tracked method in effect ([birthControl]) short-circuits
  /// before both — [computePredictionFromEntries] returns
  /// [PredictionsSuppressed] (continuous) or a pack-driven
  /// [ActivePrediction] (withdrawal-bleed) directly, so the
  /// [NotEnoughHistory]-only provisional fallback never applies to a
  /// profile with an in-effect method. The explicit `birthControl == null`
  /// guard on the fallback documents that precedence.
  CyclePrediction _resolve({
    required List<DayEntry> entries,
    required Set<LocalDate> omissions,
    required LocalDate today,
    required CycleFacts facts,
    required BirthControlState? birthControlState,
  }) {
    final birthControl = _activeBirthControlFor(birthControlState, today);
    final computed = computePredictionFromEntries(
      entries: entries,
      today: today,
      omittedCycleStarts: omissions,
      birthControl: birthControl,
    );
    if (birthControl == null &&
        computed is NotEnoughHistory &&
        facts.canSeed) {
      return seedProvisionalPrediction(facts: facts, today: today);
    }
    return computed;
  }

  /// One-shot computation from current stored entries (and the current
  /// omission list, cycle facts, and birth-control state when their
  /// providers are wired).
  Future<CyclePrediction> current(String profileId,
      {LocalDate Function()? today}) async {
    final todayOf = today ?? LocalDate.today;
    final exclusions = _exclusions;
    final omissions = exclusions == null
        ? const <LocalDate>{}
        : await exclusions.load(profileId);
    final profile = await _profiles?.findById(profileId);
    final birthControlStateFor = _birthControlStateFor;
    final birthControlState = birthControlStateFor == null
        ? null
        : await birthControlStateFor(profileId).first;
    return _resolve(
      entries: await _dayEntries.listForProfile(profileId),
      omissions: omissions,
      today: todayOf(),
      facts: CycleFacts(
        lastPeriodStart: profile?.lastPeriodStart,
        typicalCycleLengthDays: profile?.typicalCycleLengthDays,
        typicalPeriodLengthDays: profile?.typicalPeriodLengthDays,
      ),
      birthControlState: birthControlState,
    );
  }
}
