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

import '../../domain/sharing/prediction_connection_service.dart';
import '../../observability/route_names.dart';
import '../components/inline_error.dart';
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
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Enter connection code'),
          content: TextField(
            key: const ValueKey('prediction-code-field'),
            controller: controller,
            autofocus: true,
            decoration:
                const InputDecoration(hintText: 'Paste the code you received'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
    if (code == null || code.isEmpty || !mounted) return;

    String? error;
    AcceptedPredictionConnection? result;
    try {
      result = await widget.service.acceptConnection(rawToken: code);
    } on PredictionConnectionFailure catch (failure) {
      error = failure.userFacingMessage;
    } catch (_) {
      error = 'An unexpected error occurred.';
    }
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Connection failed.')));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Shared with me')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('enter-prediction-code'),
        onPressed: _enterCode,
        icon: const Icon(Icons.vpn_key_outlined),
        label: const Text('Enter code'),
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
                message: 'Could not load connections.',
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
                    Icon(Icons.calendar_month,
                        size: 48, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text('No shared predictions yet',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'When someone shares their cycle predictions with you, '
                      'their calendar appears here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
              return ListTile(
                key: ValueKey('prediction-connection-${connection.profileId}'),
                leading: const Icon(Icons.calendar_month),
                title: const Text('Cycle predictions'),
                subtitle: Text(
                    'Shared ${_formatDate(connection.acceptedAt)} • '
                    'phases only'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  buildNamedRoute<void>(
                    name: kRoutePredictionCalendarScreen,
                    builder: (_) => PredictionConnectionCalendarScreen(
                      profileId: connection.profileId,
                      profileName: 'Cycle predictions',
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

String _formatDate(DateTime utc) {
  final local = utc.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
