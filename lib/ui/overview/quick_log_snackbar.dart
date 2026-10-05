/// The confirmation shown after a "Period started today" quick log — the
/// Today card's tap (`OverviewPanel`) and the home-screen widget's
/// (`lib/app.dart`, issue #1016) both build it here, so the two can never
/// say different things about the same write.
///
/// Issue #1412: the message used to read "Recorded a medium-flow period
/// start for today" whatever happened. `quickLogFlowLevel` never lowers a
/// day already logged at medium flow or heavier, so on such a day the tap
/// leaves the flow exactly as it was; the snackbar now says that, and
/// offers no Undo because there is nothing to undo.
///
/// Both callers show it through [showQuickLogSnackBar], which answers a
/// second tap at once instead of queueing behind the first tap's message,
/// and never takes away an Undo it did not put there (issue #1472).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/logging/quick_log.dart'
    show quickLogChangesFlow;
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/action_snack_bar.dart';

/// Builds the quick-log confirmation for a day whose flow was
/// [previousFlow] before the tap (null when the day had no entry).
///
/// * The tap created the entry or raised it to the quick-log level →
///   the "recorded" message with an Undo action wired to [onUndo].
/// * The day was already at or above that level → the "already logged"
///   message, without Undo.
///
/// [contentKey] keys the message `Text` (each caller keeps its own key).
/// [accessibleNavigation] is the caller's
/// `MediaQuery.accessibleNavigationOf(context)`: the Undo snackbar leaves
/// after `kActionSnackBarDuration` unless it is true ([actionSnackBar]).
/// [onVisible] runs when the snackbar first comes on screen.
SnackBar quickLogSnackBar({
  required AppLocalizations l10n,
  required FlowLevel? previousFlow,
  required Key contentKey,
  required VoidCallback onUndo,
  required bool accessibleNavigation,
  VoidCallback? onVisible,
}) {
  if (!quickLogChangesFlow(previousFlow)) {
    return SnackBar(
      content: Text(l10n.overviewAlreadyLoggedSnackbar, key: contentKey),
      onVisible: onVisible,
    );
  }
  return actionSnackBar(
    content: Text(l10n.overviewLoggedSnackbar, key: contentKey),
    actionLabel: l10n.overviewUndo,
    onAction: onUndo,
    accessibleNavigation: accessibleNavigation,
    onVisible: onVisible,
  );
}

/// The quick-log message this flow last showed on a messenger.
class _ShownQuickLog {
  _ShownQuickLog({required this.hasUndo});

  /// Whether it carries the Undo for a write the tap made.
  final bool hasUndo;
  bool visible = false;
  bool closed = false;

  /// On screen now: it has appeared and has not been dismissed. A message
  /// still waiting its turn behind someone else's snackbar is not.
  bool get onScreen => visible && !closed;
}

final Expando<_ShownQuickLog> _lastShown = Expando<_ShownQuickLog>(
  'quick-log snackbar',
);

/// Shows the quick-log reply on [messenger]. The parameters are
/// [quickLogSnackBar]'s.
///
/// A tap is answered at once: when this flow's own earlier message is still
/// on screen it leaves first, so a second tap's reply never queues unseen
/// behind the first tap's.
///
/// Two things it never does (issue #1472, where it used to hide whatever
/// snackbar was current):
///
/// * It never dismisses a snackbar it did not show. A day-sheet delete or a
///   cycle-start change leaves an Undo on the same messenger, and that Undo
///   is the only way back; the quick-log reply waits its turn behind it.
/// * It never replaces its own Undo with a message that has none. A second
///   tap on a day the first tap just logged changes nothing, and its
///   "already logged" reply would take away the Undo for the first tap's
///   write. The message already on screen says the day is recorded, so it
///   stays.
void showQuickLogSnackBar(
  ScaffoldMessengerState messenger, {
  required AppLocalizations l10n,
  required FlowLevel? previousFlow,
  required Key contentKey,
  required VoidCallback onUndo,
  required bool accessibleNavigation,
}) {
  final hasUndo = quickLogChangesFlow(previousFlow);
  final last = _lastShown[messenger];
  if (last != null && last.onScreen) {
    if (!hasUndo && last.hasUndo) return;
    // The current snackbar is this flow's own: only then is it hidden.
    messenger.hideCurrentSnackBar();
  }
  final shown = _ShownQuickLog(hasUndo: hasUndo);
  _lastShown[messenger] = shown;
  final controller = messenger.showSnackBar(
    quickLogSnackBar(
      l10n: l10n,
      previousFlow: previousFlow,
      contentKey: contentKey,
      onUndo: onUndo,
      accessibleNavigation: accessibleNavigation,
      onVisible: () => shown.visible = true,
    ),
  );
  unawaited(controller.closed.then((_) => shown.closed = true));
}
