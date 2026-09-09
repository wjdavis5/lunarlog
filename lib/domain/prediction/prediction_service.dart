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
/// Issue #197 (performance): [watch] intentionally keeps reading the
/// profile's *full* history — predictions need the whole cycle record, not
/// just a displayed window — but memoises [computePredictionFromEntries] on
/// a cheap fingerprint of that history plus the omission set and [today]
/// (review follow-up), so a redundant emission carrying the same entries
/// (e.g. `combineLatest2` re-emitting on an exclusions-list tick, or a
/// duplicate/no-op tick from the underlying stream) reuses the previous
/// result instead of re-deriving episodes and cycle stats from scratch.
library;

import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../repositories/day_entries_repository.dart';
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
/// new `today`.
class _PredictionMemo {
  _EntriesFingerprint? _fingerprint;
  Set<LocalDate>? _omissions;
  LocalDate? _today;
  CyclePrediction? _prediction;

  /// The cached prediction when [fingerprint]/[omissions]/[today] all match
  /// the last computed call, or null when a fresh
  /// [computePredictionFromEntries] is needed.
  CyclePrediction? cached(
    _EntriesFingerprint fingerprint,
    Set<LocalDate> omissions,
    LocalDate today,
  ) {
    final prediction = _prediction;
    if (prediction == null) return null;
    if (_fingerprint != fingerprint) return null;
    if (_today != today) return null;
    if (!_sameOmissions(_omissions ?? const {}, omissions)) return null;
    return prediction;
  }

  void store(
    _EntriesFingerprint fingerprint,
    Set<LocalDate> omissions,
    LocalDate today,
    CyclePrediction value,
  ) {
    _fingerprint = fingerprint;
    _omissions = omissions;
    _today = today;
    _prediction = value;
  }
}

class CyclePredictionService {
  CyclePredictionService(this._dayEntries, {SettingsStore? settings})
      : _exclusions = settings == null ? null : CycleExclusionList(settings);

  final DayEntriesRepository _dayEntries;
  final CycleExclusionList? _exclusions;

  /// Recomputed on every emission of the profile's day-entry stream and,
  /// when a settings store is wired, of the profile's omission-list key —
  /// except when [_PredictionMemo] finds the entries fingerprint, omission
  /// set, and [today] all unchanged from the last computation (issue #197).
  /// [today] is evaluated per emission so long-lived subscriptions stay
  /// correct across midnight; it defaults to the local civil date.
  Stream<CyclePrediction> watch(String profileId,
      {LocalDate Function()? today}) {
    final todayOf = today ?? LocalDate.today;
    final entries = _dayEntries.watchForProfile(profileId);
    final exclusions = _exclusions;
    final memo = _PredictionMemo();
    if (exclusions == null) {
      return entries.map((list) => _predictionFor(
            memo: memo,
            entries: list,
            omissions: const {},
            today: todayOf(),
          ));
    }
    return combineLatest2(entries, exclusions.watch(profileId)).map(
      (latest) => _predictionFor(
        memo: memo,
        entries: latest.$1,
        omissions: latest.$2,
        today: todayOf(),
      ),
    );
  }

  CyclePrediction _predictionFor({
    required _PredictionMemo memo,
    required List<DayEntry> entries,
    required Set<LocalDate> omissions,
    required LocalDate today,
  }) {
    final fingerprint = _fingerprintOf(entries);
    final cached = memo.cached(fingerprint, omissions, today);
    if (cached != null) return cached;
    final prediction = computePredictionFromEntries(
      entries: entries,
      today: today,
      omittedCycleStarts: omissions,
    );
    memo.store(fingerprint, omissions, today, prediction);
    return prediction;
  }

  /// One-shot computation from current stored entries (and the current
  /// omission list, when settings are wired).
  Future<CyclePrediction> current(String profileId,
      {LocalDate Function()? today}) async {
    final todayOf = today ?? LocalDate.today;
    final exclusions = _exclusions;
    final omissions = exclusions == null
        ? const <LocalDate>{}
        : await exclusions.load(profileId);
    return computePredictionFromEntries(
      entries: await _dayEntries.listForProfile(profileId),
      today: todayOf(),
      omittedCycleStarts: omissions,
    );
  }
}
