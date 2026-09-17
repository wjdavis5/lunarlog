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
///
/// Issue #528: a [lifecycleModeFor] provider (a `Stream<LifecycleMode>` per
/// profile — the same drift `profile_modes` row #233 already watches, just
/// its `mode` column instead of its birth-control columns) joins the combine
/// too. [_resolve] checks it first, before either the birth-control branch
/// or the ordinary history computation: `pregnancy`/`postpartum`/
/// `perimenopause` always return [PredictionsSuppressed], regardless of what
/// history or birth-control state the profile also carries. A null provider
/// (tests, unconfigured wiring) keeps the exact pre-#528 behavior — every
/// profile resolves as [LifecycleMode.tracking].
library;

import 'dart:async';

import '../birth_control.dart';
import '../models/day_entry.dart';
import '../models/lifecycle_mode.dart';
import '../models/local_date.dart';
import '../models/profile.dart';
import '../repositories/cycle_overrides_repository.dart';
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
/// calendar is covered by the date alone.) Issue #528 adds [LifecycleMode]
/// to the same key for the same reason: a life-stage switch must re-derive
/// even when entries/facts/birth-control state are unchanged.
class _PredictionMemo {
  _EntriesFingerprint? _fingerprint;
  Set<LocalDate>? _omissions;
  LocalDate? _today;
  CycleFacts? _facts;
  BirthControlState? _birthControlState;
  LifecycleMode? _lifecycleMode;
  CyclePrediction? _prediction;

  /// The cached prediction when [fingerprint]/[omissions]/[today]/[facts]/
  /// [birthControlState]/[lifecycleMode] all match the last computed call,
  /// or null when a fresh [computePredictionFromEntries] is needed.
  CyclePrediction? cached(
    _EntriesFingerprint fingerprint,
    Set<LocalDate> omissions,
    LocalDate today,
    CycleFacts facts,
    BirthControlState? birthControlState,
    LifecycleMode lifecycleMode,
  ) {
    final prediction = _prediction;
    if (prediction == null) return null;
    if (_fingerprint != fingerprint) return null;
    if (_today != today) return null;
    if (!_sameOmissions(_omissions ?? const {}, omissions)) return null;
    if (_facts != facts) return null;
    if (_birthControlState != birthControlState) return null;
    if (_lifecycleMode != lifecycleMode) return null;
    return prediction;
  }

  void store(
    _EntriesFingerprint fingerprint,
    Set<LocalDate> omissions,
    LocalDate today,
    CycleFacts facts,
    BirthControlState? birthControlState,
    LifecycleMode lifecycleMode,
    CyclePrediction value,
  ) {
    _fingerprint = fingerprint;
    _omissions = omissions;
    _today = today;
    _facts = facts;
    _birthControlState = birthControlState;
    _lifecycleMode = lifecycleMode;
    _prediction = value;
  }
}

/// Issue LLA-070: ticks immediately, then re-ticks only when [today]
/// (re-read on every [ticks] event) reports a civil date different from
/// the last one seen — never on every poll. [ticks] defaults to a real
/// `Stream.periodic([pollInterval])`; tests inject a fully controlled
/// stream and a mutable [today] instead, so this is testable with no real
/// timer/sleep at all (see `prediction_service_test.dart`'s own tests).
///
/// This is the REAL, production seam that actually closes the finding (a
/// long-lived app process must recompute across a civil-date rollover
/// with no data emission) — [CyclePredictionService.watch] folds it into
/// its combine.
///
/// **Review round 1 fix:** the first version of this ticker re-emitted on
/// every single poll regardless of whether the date had actually changed,
/// which propagated all the way through `combineLatest3` into every
/// prediction consumer once a minute — most importantly
/// `ReminderCoordinator`, which replans (and reschedules every pending
/// local notification via `rescheduleAll`) on every prediction emission,
/// so that shape was 1,440 needless replans a day per profile. Comparing
/// [today] against the last-seen date here, once, is what the rest of the
/// pipeline relies on to never see a same-day tick at all — no separate
/// suppression is needed downstream (`CyclePredictionService`'s own
/// `#197` memo already collapses a same-content recompute to the same
/// cached instance when it *does* run, but with this fix a same-day tick
/// no longer reaches that combine to trigger one in the first place).
///
/// Deliberately **not** [CyclePredictionService]'s own default: a
/// `Stream.periodic` keeps a live platform [Timer] running for as long as
/// anything is subscribed, and the many unit/widget tests that construct
/// a [CyclePredictionService] (or the app shell) directly — never
/// disposing it through any app-level teardown — would otherwise fail
/// `flutter_test`'s zero-pending-timers check. `main.dart` (by way of
/// `LunarLogRoot.dateTicker`/`buildAppDependencies`) wires this in
/// explicitly for the actual running app; every other caller gets
/// [CyclePredictionService.new]'s tick-once default instead, matching
/// every other combine source's "replay current value on listen"
/// convention with no timer at all.
///
/// Built on a plain [StreamController] with explicit `onListen`/`onCancel`
/// (the same shape `combine_latest.dart`'s combinators use) rather than an
/// `async*` generator's `await for` on [ticks]: cancelling the *outer*
/// subscription of an `async*` function does not propagate into an inner
/// stream it is currently awaiting via `await for` — the generator (and
/// this function's caller) would hang forever waiting for [ticks]' next
/// event or close, since [ticks] (a real `Stream.periodic` in production)
/// never naturally does either. Constructing the controller directly and
/// cancelling [ticks]' own subscription in `onCancel` is what makes this
/// function's stream actually stop when its listener does.
Stream<void> dateRolloverTicker({
  Duration pollInterval = const Duration(minutes: 1),
  LocalDate Function() today = LocalDate.today,
  Stream<void>? ticks,
}) {
  late final StreamController<void> controller;
  StreamSubscription<void>? pollSub;
  LocalDate? lastDate;

  controller = StreamController<void>(
    onListen: () {
      lastDate = today();
      controller.add(null);
      final polls = ticks ?? Stream<void>.periodic(pollInterval, (_) {});
      pollSub = polls.listen(
        (_) {
          final current = today();
          if (current == lastDate) return;
          lastDate = current;
          controller.add(null);
        },
        onError: controller.addError,
        onDone: () => unawaited(controller.close()),
      );
    },
    onCancel: () => pollSub?.cancel(),
  );
  return controller.stream;
}

/// [CyclePredictionService]'s own default [CyclePredictionService.new]
/// `dateTicker`: ticks exactly once, immediately, and never again — no
/// platform [Timer] of any kind, so every existing caller that never
/// passes `dateTicker` keeps behaving exactly as before issue LLA-070.
/// Satisfies [combineLatest3]'s "every source must emit once" requirement
/// without ever contributing a *second* tick; only [dateRolloverTicker]
/// (opted into explicitly, see its own doc comment) actually closes the
/// civil-date-rollover gap.
Stream<void> _tickOnceDateTicker() => Stream<void>.value(null);

class CyclePredictionService {
  /// [cycleOverrides] (issue #568 (b)) is forwarded to [CycleExclusionList]
  /// unchanged — see that class's doc comment for why it is optional and
  /// what a null value keeps. [dateTicker] (issue LLA-070) is the seam
  /// [watch] merges into its combine to recompute across a civil-date
  /// rollover with no data emission; defaults to [_tickOnceDateTicker]
  /// (no timer at all — see its own doc comment for why). The composition
  /// root passes [dateRolloverTicker] explicitly for the real running app;
  /// tests that exercise the rollover itself inject a fully controlled
  /// stream of their own — never a real timer/sleep.
  CyclePredictionService(this._dayEntries,
      {SettingsStore? settings,
      CycleOverridesRepository? cycleOverrides,
      ProfilesRepository? profiles,
      Stream<BirthControlState?> Function(String profileId)?
          birthControlStateFor,
      Stream<LifecycleMode> Function(String profileId)? lifecycleModeFor,
      Stream<void> Function()? dateTicker})
      : _settings = settings,
        _exclusions = settings == null
            ? null
            : CycleExclusionList(settings, overrides: cycleOverrides),
        // A named parameter cannot be private, so this direct
        // pass-through cannot be an initializing formal (the same reason
        // the coordinator/publisher files carry file-level ignores).
        // ignore: prefer_initializing_formals
        _profiles = profiles,
        // ignore: prefer_initializing_formals
        _birthControlStateFor = birthControlStateFor,
        // ignore: prefer_initializing_formals
        _lifecycleModeFor = lifecycleModeFor,
        _dateTicker = dateTicker ?? _tickOnceDateTicker;

  final DayEntriesRepository _dayEntries;
  final SettingsStore? _settings;
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

  /// Issue #528: per-profile `profile_modes` life-stage mode watcher.
  /// [_resolve] short-circuits to [PredictionsSuppressed] for
  /// `pregnancy`/`postpartum`/`perimenopause` before either the
  /// birth-control branch or the ordinary history computation runs. Null
  /// keeps the exact pre-#528 behavior — every profile resolves as
  /// [LifecycleMode.tracking].
  final Stream<LifecycleMode> Function(String profileId)? _lifecycleModeFor;

  /// Issue LLA-070: the date-rollover ticker [watch] folds into its
  /// combine. Defaults to [_tickOnceDateTicker]; see [dateRolloverTicker]'s
  /// doc comment for the real (production) ticker and why it is not the
  /// default here.
  final Stream<void> Function() _dateTicker;

  /// Recomputed on every emission of the profile's day-entry stream and,
  /// when a settings store is wired, of the profile's omission-list key —
  /// except when [_PredictionMemo] finds the entries fingerprint, omission
  /// set, facts, and [today] all unchanged from the last computation
  /// (issue #197). [today] is evaluated per emission so long-lived
  /// subscriptions stay correct across midnight; it defaults to the local
  /// civil date.
  ///
  /// Issue #225: when predictions are disabled for this profile in settings,
  /// emits [PredictionsDisabled] immediately.
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
    // Issue #528: the life-stage mode joins on top of the entries/facts/
    // birth-control triple, folded down to a flat record the same way
    // exclusions folds on below.
    final withMode = combineLatest2(core, _lifecycleModeForProfile(profileId))
        .map((latest) =>
            (latest.$1.$1, latest.$1.$2, latest.$1.$3, latest.$2));
    final Stream<
            (
              List<DayEntry>,
              Set<LocalDate>,
              CycleFacts,
              BirthControlState?,
              LifecycleMode
            )>
        withExclusions;
    if (exclusions == null) {
      withExclusions = withMode.map(
        (latest) =>
            (latest.$1, const <LocalDate>{}, latest.$2, latest.$3, latest.$4),
      );
    } else {
      withExclusions = combineLatest2(withMode, exclusions.watch(profileId))
          .map((latest) => (
                latest.$1.$1,
                latest.$2,
                latest.$1.$2,
                latest.$1.$3,
                latest.$1.$4,
              ));
    }
    // Issue LLA-070: the date ticker joins the combine purely as a trigger
    // -- its own value is never read -- so a tick re-runs this map with a
    // fresh todayOf() even when entries/settings/facts/mode/enabled are
    // all unchanged. The #197 memo below still gates the actual
    // recomputation on todayOf() having genuinely changed, so a tick that
    // lands mid-day (today unchanged) is a no-op past the memo check, not
    // a wasted recompute.
    return combineLatest3(
      withExclusions,
      _predictionsEnabledFor(profileId),
      _dateTicker(),
    ).map((latest) {
      final enabled = latest.$2;
      if (!enabled) return const PredictionsDisabled();
      final data = latest.$1;
      return _predictionFor(
        memo: memo,
        entries: data.$1,
        omissions: data.$2,
        today: todayOf(),
        facts: data.$3,
        birthControlState: data.$4,
        lifecycleMode: data.$5,
      );
    });
  }

  Stream<bool> _predictionsEnabledFor(String profileId) {
    final settings = _settings;
    if (settings == null) return Stream.value(true);
    return settings
        .watch(predictionsEnabledSettingKey(profileId))
        .map(parsePredictionsEnabled);
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

  /// The profile's life-stage mode (issue #528), or
  /// [LifecycleMode.tracking] when no [_lifecycleModeFor] provider is
  /// wired. Re-emitted on every `profile_modes` row change; [LifecycleMode]
  /// is an enum so the #197 memo's equality check on it is exact.
  Stream<LifecycleMode> _lifecycleModeForProfile(String profileId) {
    final provider = _lifecycleModeFor;
    if (provider == null) return Stream.value(LifecycleMode.tracking);
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
    required LifecycleMode lifecycleMode,
  }) {
    final fingerprint = _fingerprintOf(entries);
    final cached = memo.cached(fingerprint, omissions, today, facts,
        birthControlState, lifecycleMode);
    if (cached != null) return cached;
    final prediction = _resolve(
      entries: entries,
      omissions: omissions,
      today: today,
      facts: facts,
      birthControlState: birthControlState,
      lifecycleMode: lifecycleMode,
    );
    memo.store(fingerprint, omissions, today, facts, birthControlState,
        lifecycleMode, prediction);
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
  ///
  /// Issue #528: [lifecycleMode] is checked first, ahead of both #218 and
  /// #233 — `pregnancy`/`postpartum`/`perimenopause` return
  /// [PredictionsSuppressed] outright, regardless of what history or
  /// birth-control state the profile also carries. Unlike the birth-control
  /// branch (owned by [computePredictionFromEntries], since it also
  /// produces a pack-driven [ActivePrediction] for a withdrawal-bleed
  /// method), this branch has only one outcome, so it lives here rather
  /// than adding a [LifecycleMode] parameter to that pure function.
  CyclePrediction _resolve({
    required List<DayEntry> entries,
    required Set<LocalDate> omissions,
    required LocalDate today,
    required CycleFacts facts,
    required BirthControlState? birthControlState,
    required LifecycleMode lifecycleMode,
  }) {
    if (_suppressesPrediction(lifecycleMode)) {
      return PredictionsSuppressed(lifecycleMode: lifecycleMode);
    }
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

  /// The life-stage modes issue #528 suppresses period prediction for: none
  /// of these are the regular ovulatory cycle the averaging model assumes.
  /// `tracking` and `conceive` are unaffected — conceive is still trying to
  /// predict a fertile window from an ordinary cycle.
  static bool _suppressesPrediction(LifecycleMode mode) => switch (mode) {
        LifecycleMode.pregnancy ||
        LifecycleMode.postpartum ||
        LifecycleMode.perimenopause =>
          true,
        LifecycleMode.tracking || LifecycleMode.conceive => false,
      };

  /// One-shot computation from current stored entries (and the current
  /// omission list, cycle facts, and birth-control state when their
  /// providers are wired).
  ///
  /// Issue #225: returns [PredictionsDisabled] when predictions are turned
  /// off for this profile.
  Future<CyclePrediction> current(String profileId,
      {LocalDate Function()? today}) async {
    final settings = _settings;
    if (settings != null) {
      final raw = await settings.get(predictionsEnabledSettingKey(profileId));
      if (!parsePredictionsEnabled(raw)) {
        return const PredictionsDisabled();
      }
    }
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
    final lifecycleModeFor = _lifecycleModeFor;
    final lifecycleMode = lifecycleModeFor == null
        ? LifecycleMode.tracking
        : await lifecycleModeFor(profileId).first;
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
      lifecycleMode: lifecycleMode,
    );
  }
}
