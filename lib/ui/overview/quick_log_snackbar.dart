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
/// Both callers hide the snackbar already on screen before showing this one
/// (`ScaffoldMessengerState.hideCurrentSnackBar`), so a second tap is
/// answered at once instead of queueing behind the first tap's message.
library;

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
SnackBar quickLogSnackBar({
  required AppLocalizations l10n,
  required FlowLevel? previousFlow,
  required Key contentKey,
  required VoidCallback onUndo,
  required bool accessibleNavigation,
}) {
  if (!quickLogChangesFlow(previousFlow)) {
    return SnackBar(
      content: Text(l10n.overviewAlreadyLoggedSnackbar, key: contentKey),
    );
  }
  return actionSnackBar(
    content: Text(l10n.overviewLoggedSnackbar, key: contentKey),
    actionLabel: l10n.overviewUndo,
    onAction: onUndo,
    accessibleNavigation: accessibleNavigation,
  );
}
