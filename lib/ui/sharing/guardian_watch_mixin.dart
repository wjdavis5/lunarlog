/// Shared boilerplate (issue #540) behind the guardian-watch subscriptions
/// duplicated across `MonthCalendar`, `OverviewPanel`, `TodayLogFab`,
/// `AnalysisTab` (each an independent, near-identical
/// subscribe-reset-on-switch `StreamSubscription`), and `CareNotesScreen`
/// (a `StreamBuilder` over the same repository stream). None of the five
/// passed `onError` — a stream error (e.g. from a row this build's mapper
/// cannot make sense of) would have propagated as an unhandled root-zone
/// async error for the four `StreamSubscription` sites, or simply frozen
/// the guardians list for `CareNotesScreen`'s `StreamBuilder`, rather than
/// degrading the way every other consumer of this repository now does.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;

/// [repository]'s guardians stream for [profileId], with a stream error
/// recorded (type-only breadcrumb + Sentry capture, KTD12-style) and then
/// dropped rather than forwarded — the one place this logging happens, so
/// every consumer (a manual `.listen()` or a `StreamBuilder`) gets it for
/// free instead of needing its own `onError`.
Stream<List<ProfileGuardian>> watchGuardiansForProfileSafely(
  ProfileGuardiansRepository repository,
  String profileId,
) =>
    repository.watchForProfile(profileId).handleError(
      (Object error, StackTrace stackTrace) {
        defaultBreadcrumbLog.record(
            'guardianWatch', 'watchForProfile failed: ${error.runtimeType}');
        unawaited(Sentry.captureException(error, stackTrace: stackTrace));
      },
    );

/// Mixed into a [State] that keeps a live guardians list for one profile.
/// The mixing class still owns its own `_guardians` field and `setState`
/// call (this only centralises the subscription lifecycle), so existing
/// build-method reads of that field are untouched.
mixin GuardianWatchMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<List<ProfileGuardian>>? _guardianWatchSub;

  /// (Re)subscribes to [repository]'s guardians stream for [profileId] via
  /// [watchGuardiansForProfileSafely], cancelling any previous subscription
  /// first. Calls [onGuardians] with an empty list immediately — before
  /// the new subscription's first emission arrives — matching every call
  /// site's existing reset discipline, then again on every emission
  /// (guarded by [mounted]). A null [repository] cancels and resets
  /// without subscribing to anything.
  void watchGuardiansForProfile(
    ProfileGuardiansRepository? repository,
    String profileId,
    void Function(List<ProfileGuardian> guardians) onGuardians,
  ) {
    unawaited(_guardianWatchSub?.cancel());
    onGuardians(const []);
    if (repository == null) return;
    _guardianWatchSub =
        watchGuardiansForProfileSafely(repository, profileId).listen(
      (guardians) {
        if (!mounted) return;
        onGuardians(guardians);
      },
    );
  }

  /// Cancels the current subscription, if any. Call from the mixing
  /// state's own `dispose()`.
  void disposeGuardianWatch() {
    unawaited(_guardianWatchSub?.cancel());
    _guardianWatchSub = null;
  }
}
