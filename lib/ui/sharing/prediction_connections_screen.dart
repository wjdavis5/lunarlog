/// The recipient's list of prediction-only connections (issue #151):
/// every profile currently sharing derived phases with this account, each
/// opening the phase-only calendar. Also the manual "Enter code" entry
/// point for a redemption that did not arrive as a deep link.
///
/// Data is read on demand from the server ([PredictionConnectionService
/// .listIncomingConnections]) — there is no local table behind incoming
/// connections and nothing syncs to this device.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/prediction_connection_failure_copy.dart';

import '../../domain/sharing/prediction_connection_service.dart';
import '../../observability/route_names.dart';
import '../components/destructive_button.dart';
import '../components/inline_error.dart';
import '../l10n/dates.dart' as dates;
import '../routes.dart';
import 'prediction_connection_calendar_screen.dart';

class PredictionConnectionsScreen extends StatefulWidget {
  const PredictionConnectionsScreen({
    super.key,
    required this.service,
    this.onConnected,
  });

  final PredictionConnectionService service;

  /// Called after a manual code is redeemed — the shell pushes the
  /// calendar for the newly connected profile.
  final void Function(AcceptedPredictionConnection result)? onConnected;

  @override
  State<PredictionConnectionsScreen> createState() =>
      _PredictionConnectionsScreenState();
}

class _PredictionConnectionsScreenState
    extends State<PredictionConnectionsScreen> {
  late Future<List<IncomingPredictionConnection>> _connectionsFuture;

  /// Issue #462: per-row busy guard so a "Stop receiving" tap disables
  /// itself while its own RPC is in flight, mirroring `ManageGuardiansScreen
  /// `'s `_revokingUserIds` pattern.
  final Set<String> _leavingConnectionIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _connectionsFuture = widget.service.listIncomingConnections();
    });
  }

  Future<void> _enterCode() async {
    final code = await _promptForCode();
    if (code == null) return;
    await _redeemCode(code);
  }

  /// Issue #574: was a `TextEditingController()` constructed directly
  /// inside `showDialog`'s `builder`, which Flutter may invoke more than
  /// once (a theme/MediaQuery change, a route rebuild) — each invocation
  /// minted a new, never-disposed controller, and a rotation mid-dialog
  /// detached the TextField from whichever controller the Connect button
  /// still read. `_EnterCodeDialog` owns one controller for the dialog's
  /// whole lifetime and disposes it. Returns null on a cancelled/empty
  /// dialog, or if the screen was unmounted while it was open.
  Future<String?> _promptForCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => const _EnterCodeDialog(),
    );
    if (code == null || code.isEmpty || !mounted) return null;
    return code;
  }

  /// Redeems [code] against the server, then either shows the failure or
  /// navigates to the newly connected profile's calendar. Split out of
  /// [_enterCode] (a pure extraction, no behavior change) to keep both
  /// methods under the CRAP-10 complexity gate.
  Future<void> _redeemCode(String code) async {
    PredictionConnectionFailure? typedFailure;
    bool unexpectedFailure = false;
    AcceptedPredictionConnection? result;
    try {
      result = await widget.service.acceptConnection(rawToken: code);
    } on PredictionConnectionFailure catch (failure) {
      typedFailure = failure;
    } catch (_) {
      unexpectedFailure = true;
    }
    if (!mounted) return;
    if (result == null) {
      _showRedeemFailure(typedFailure, unexpectedFailure);
      return;
    }
    _load();
    widget.onConnected?.call(result);
    // A fresh final: flow analysis cannot keep `result` promoted across
    // the builder closure below.
    final AcceptedPredictionConnection connected = result;
    Navigator.of(context).push(
      buildNamedRoute<void>(
        name: kRoutePredictionCalendarScreen,
        builder: (_) => PredictionConnectionCalendarScreen(
          profileId: connected.profileId,
          profileName: connected.profileName,
          service: widget.service,
        ),
      ),
    );
  }

  /// Issue #462: the recipient's own "Stop receiving" action — a
  /// confirm-then-call flow calling [PredictionConnectionService
  /// .leaveConnection] rather than [PredictionConnectionService
  /// .revokeConnection] (the sharer/primary-guardian path), reaching the
  /// identical terminal state server-side.
  Future<void> _stopReceiving(IncomingPredictionConnection connection) async {
    if (_leavingConnectionIds.contains(connection.connectionId)) return;
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      routeSettings:
          const RouteSettings(name: kRouteStopReceivingPredictionsDialog),
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sharingPredictionConnectionsStopTitle),
        content: SingleChildScrollView(
          child: Text(l10n.sharingPredictionConnectionsStopBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.sharingPredictionConnectionsCancel),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.sharingPredictionConnectionsStopAction),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _leavingConnectionIds.add(connection.connectionId));
    try {
      await widget.service.leaveConnection(
        connectionId: connection.connectionId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.sharingPredictionConnectionsStopped)),
        );
        _load();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.sharingPredictionConnectionsStopFailed),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(
          () => _leavingConnectionIds.remove(connection.connectionId),
        );
      }
    }
  }

  void _showRedeemFailure(
    PredictionConnectionFailure? typedFailure,
    bool unexpectedFailure,
  ) {
    final l10n = AppLocalizations.of(context);
    final error = typedFailure != null
        ? predictionConnectionFailureCopy(l10n, typedFailure)
        : unexpectedFailure
        ? l10n.sharingUnexpectedError
        : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? l10n.sharingPredictionConnectionsFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sharingPredictionConnectionsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('enter-prediction-code'),
        onPressed: _enterCode,
        icon: const Icon(Icons.vpn_key_outlined),
        label: Text(l10n.predictionEnterLinkAction),
      ),
      body: FutureBuilder<List<IncomingPredictionConnection>>(
        future: _connectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: InlineError(
                key: const ValueKey('prediction-connections-error'),
                message: l10n.sharingPredictionConnectionsLoadError,
                onRetry: _load,
              ),
            );
          }
          final connections = snapshot.data ?? const [];
          if (connections.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.sharingPredictionConnectionsEmptyTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.sharingPredictionConnectionsEmptyBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: connections.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final connection = connections[index];
              final leaving =
                  _leavingConnectionIds.contains(connection.connectionId);
              return ListTile(
                key: ValueKey('prediction-connection-${connection.profileId}'),
                leading: const Icon(Icons.calendar_month),
                title: Text(l10n.sharingPredictionConnectionsCyclePredictions),
                subtitle: Text(
                  l10n.sharingPredictionConnectionsSharedSubtitle(
                    _formatDate(context, connection.acceptedAt),
                  ),
                ),
                // Issue #462: "Stop receiving" sits beside the disclosure
                // chevron rather than replacing it — the row itself still
                // navigates to the calendar.
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    leaving
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            key: ValueKey(
                              'stop-receiving-${connection.connectionId}',
                            ),
                            icon: const Icon(Icons.link_off),
                            tooltip: l10n.sharingPredictionConnectionsStopTooltip,
                            onPressed: () => _stopReceiving(connection),
                          ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  buildNamedRoute<void>(
                    name: kRoutePredictionCalendarScreen,
                    builder: (_) => PredictionConnectionCalendarScreen(
                      profileId: connection.profileId,
                      profileName:
                          l10n.sharingPredictionConnectionsCyclePredictions,
                      service: widget.service,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The "Enter connection code" dialog body (issue #574): a small
/// [StatefulWidget] so its [TextEditingController] survives a rebuild
/// (theme/MediaQuery change, route rebuild) of the dialog rather than
/// being reminted by `showDialog`'s `builder` on every such rebuild, and
/// is disposed exactly once when the dialog itself is.
class _EnterCodeDialog extends StatefulWidget {
  const _EnterCodeDialog();

  @override
  State<_EnterCodeDialog> createState() => _EnterCodeDialogState();
}

class _EnterCodeDialogState extends State<_EnterCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.predictionEnterLinkTitle),
      content: TextField(
        key: const ValueKey('prediction-code-field'),
        controller: _controller,
        autofocus: true,
        // #165: the dialog's only text field — "done" is the Connect
        // action (identical to the button's pop-with-trimmed-code).
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.of(context).pop(_controller.text.trim()),
        decoration: InputDecoration(
          hintText: l10n.predictionEnterLinkHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.sharingPredictionConnectionsCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.sharingPredictionConnectionsConnect),
        ),
      ],
    );
  }
}

/// #554: locale-aware short date -- was a hand-rolled, always `YYYY-MM-DD`
/// string.
String _formatDate(BuildContext context, DateTime utc) =>
    dates.formatShortDate(utc.toLocal(), locale: dates.calendarLocale(context));
