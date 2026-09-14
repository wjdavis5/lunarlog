/// Shared boilerplate (issue #642, LLA-010) behind the entry-existence
/// subscriptions the CSV and clinical (FHIR) export tiles each need: "does
/// *any* observed profile have at least one live day entry" as its own
/// bounded, reactive signal — one `Stream<bool>` per profile via
/// [DayEntriesRepository.watchHasAnyEntries] (bounded: a `LIMIT 1` existence
/// check, never the entries themselves) — instead of deriving it from the
/// *profiles* stream's own re-emissions (the tiles' pre-#642 shape).
///
/// That distinction matters under the app shell's retained [IndexedStack]
/// (issue #182): More stays mounted once built, so a day entry logged on
/// Today/Calendar never makes the *profiles* stream tick, and a
/// profiles-stream-derived `hasEntries` would stay stale until some
/// unrelated profile change forced a re-check.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

/// Mixed into a [State] that needs a live "any of these profiles has at
/// least one day entry" boolean. The mixing class still owns its own build
/// method (this only centralises subscription lifecycle and triggers its
/// own `setState`) — call [watchEntryExistence] whenever the tracked set of
/// profile ids may have changed (safe to call on every emission of the
/// owning profiles stream; it diffs against the previous set and only
/// touches subscriptions that actually changed) and read [hasAnyEntries]
/// from `build`.
mixin EntryExistenceWatchMixin<T extends StatefulWidget> on State<T> {
  final Map<String, StreamSubscription<bool>> _entrySubs = {};
  final Map<String, bool> _perProfileHasEntries = {};

  /// Whether any currently-observed profile has at least one live day
  /// entry, per the latest emission seen for it. A profile with no
  /// emission yet (subscription just started, or its stream errored) reads
  /// as `false` — the same fail-closed default every export tile already
  /// used before #642.
  bool get hasAnyEntries => _perProfileHasEntries.values.any((value) => value);

  /// (Re)subscribes to [repository]'s existence stream for every id in
  /// [profileIds], cancelling and dropping any id no longer listed. A null
  /// [repository] drops every subscription without adding new ones
  /// (fail-closed, mirroring the tiles' existing behaviour when no
  /// repository is provided). Idempotent: calling it again with the same
  /// [profileIds] touches nothing.
  void watchEntryExistence(
    DayEntriesRepository? repository,
    Iterable<String> profileIds,
  ) {
    final wanted = repository == null ? const <String>{} : profileIds.toSet();
    for (final id in _entrySubs.keys.toList()) {
      if (wanted.contains(id)) continue;
      unawaited(_entrySubs.remove(id)?.cancel());
      _perProfileHasEntries.remove(id);
    }
    for (final id in wanted) {
      if (_entrySubs.containsKey(id)) continue;
      _entrySubs[id] = repository!
          .watchHasAnyEntries(id)
          .listen(
            (value) {
              if (!mounted) return;
              setState(() => _perProfileHasEntries[id] = value);
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint(
                'lunarlog entry-existence: watchHasAnyEntries failed '
                '(${error.runtimeType})',
              );
              if (mounted) setState(() => _perProfileHasEntries[id] = false);
            },
          );
    }
  }

  /// Cancels every subscription. Call from the mixing state's own
  /// `dispose()`.
  void disposeEntryExistenceWatch() {
    for (final sub in _entrySubs.values) {
      unawaited(sub.cancel());
    }
    _entrySubs.clear();
    _perProfileHasEntries.clear();
  }
}
