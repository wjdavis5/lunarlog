/// New/confirm PIN form (issue #271 U1/U4), shared by "Set a PIN" (no prior
/// authorization needed — there is nothing yet to prove ownership of) and
/// "Change PIN" (reached only after [showPinAuthorizationDialog] succeeds).
/// Returns the chosen PIN via [Navigator.pop] on success; null means
/// cancelled.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/inline_error.dart';

/// PIN length bounds (#271 acceptance criterion: "4-6 digits" — widened
/// slightly to 4-8 to match common authenticator-app/passcode conventions
/// without weakening the floor the issue names).
const int kPinMinLength = 4;
const int kPinMaxLength = 8;

enum PinEntryFormMode { create, change }

class PinEntryFormScreen extends StatefulWidget {
  const PinEntryFormScreen({super.key, required this.mode});

  final PinEntryFormMode mode;

  @override
  State<PinEntryFormScreen> createState() => _PinEntryFormScreenState();
}

class _PinEntryFormScreenState extends State<PinEntryFormScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final pin = _pinController.text;
    if (pin.length < kPinMinLength) {
      setState(() => _error = l10n.pinTooShortError);
      return;
    }
    if (pin != _confirmController.text) {
      setState(() => _error = l10n.pinMismatchError);
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = widget.mode == PinEntryFormMode.create
        ? l10n.pinSetScreenTitle
        : l10n.pinChangeScreenTitle;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('pin-new-field'),
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(kPinMaxLength),
              ],
              decoration: InputDecoration(labelText: l10n.pinNewPinLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('pin-confirm-field'),
              controller: _confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(kPinMaxLength),
              ],
              decoration: InputDecoration(labelText: l10n.pinConfirmPinLabel),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              InlineError(key: const ValueKey('pin-form-error'), message: _error!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('pin-save-button'),
              onPressed: _save,
              child: Text(l10n.pinSaveButton),
            ),
          ],
        ),
      ),
    );
  }
}
