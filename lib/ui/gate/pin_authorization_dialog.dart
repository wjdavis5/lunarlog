/// The "current PIN or device auth" gate issue #271 requires before a PIN
/// can be changed or removed. Shared by [PinSettingsScreen]'s "Change PIN"
/// and "Turn off PIN" actions.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/components/inline_error.dart';

class _PinAuthorizationDialog extends StatefulWidget {
  const _PinAuthorizationDialog({required this.gate});

  final GateController gate;

  @override
  State<_PinAuthorizationDialog> createState() =>
      _PinAuthorizationDialogState();
}

class _PinAuthorizationDialogState extends State<_PinAuthorizationDialog> {
  final TextEditingController _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyCurrentPin() async {
    final pin = _pinController.text;
    if (pin.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.gate.verifyPinForSettings(pin);
    if (!mounted) return;
    if (result.outcome == PinCheckOutcome.correct) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = AppLocalizations.of(context).pinWrongCurrentError;
    });
  }

  Future<void> _useDeviceCredential() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final granted =
        await widget.gate.duringSystemUi(widget.gate.reauthenticate);
    if (!mounted) return;
    if (granted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.pinCurrentPinLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('pin-auth-current-field'),
            controller: _pinController,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.pinCurrentPinLabel),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            InlineError(
                key: const ValueKey('pin-auth-error'), message: _error!),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('pin-auth-device-credential'),
          onPressed: _busy ? null : _useDeviceCredential,
          child: const Text('Use device credential instead'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pin-auth-verify'),
          onPressed: _busy ? null : _verifyCurrentPin,
          child: Text(l10n.mfaStepUpConfirmButton),
        ),
      ],
    );
  }
}

/// Shows [_PinAuthorizationDialog] and returns true only when the operator
/// proved the current PIN or a fresh device credential (#271 "requires the
/// current PIN or device auth"). False/null means cancelled or declined.
Future<bool> showPinAuthorizationDialog(
  BuildContext context,
  GateController gate,
) async =>
    await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: kRoutePinAuthorizationDialog),
      builder: (_) => _PinAuthorizationDialog(gate: gate),
    ) ??
    false;
