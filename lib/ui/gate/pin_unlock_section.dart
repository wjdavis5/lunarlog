/// The lock screen's in-app PIN entry (issue #271 D-6): rendered by
/// [LockScreen] in place of the device-credential content once
/// [GateController.pinRequired] is true — either as the second layer after
/// a granted device credential, or standing alone on a device with none
/// enrolled at all.
///
/// A [StatefulWidget] (unlike the rest of [LockScreen]) because it owns its
/// own text field, in-flight/error state, and a lockout countdown timer —
/// none of which belongs on [GateController] itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/inline_error.dart';

class PinUnlockSection extends StatefulWidget {
  const PinUnlockSection({super.key, required this.controller});

  final GateController controller;

  @override
  State<PinUnlockSection> createState() => _PinUnlockSectionState();
}

class _PinUnlockSectionState extends State<PinUnlockSection> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _submitting = false;
  String? _error;
  DateTime? _lockedUntil;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // A relaunch mid-lockout should show the countdown immediately rather
    // than waiting for another wrong attempt to discover it.
    unawaited(widget.controller.pinLockoutState().then((state) {
      if (mounted && state.lockedUntil != null) _armCountdown(state.lockedUntil);
    }));
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool get _isLockedOut =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now());

  Future<void> _submit() async {
    final pin = _pinController.text;
    if (_submitting || pin.isEmpty || _isLockedOut) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.controller.submitPin(pin);
      if (!mounted) return;
      _handleResult(result);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleResult(PinVerification result) {
    final l10n = AppLocalizations.of(context);
    switch (result.outcome) {
      case PinCheckOutcome.correct:
        // GateController has already unlocked and will notify; this widget
        // is about to be torn down by GateShell's rebuild.
        _pinController.clear();
      case PinCheckOutcome.incorrect:
        _pinController.clear();
        setState(() => _error =
            l10n.pinLockScreenIncorrect(result.remainingFreeAttempts));
      case PinCheckOutcome.lockedOut:
        _pinController.clear();
        _armCountdown(result.lockedUntil);
    }
  }

  void _armCountdown(DateTime? lockedUntil) {
    _countdownTimer?.cancel();
    setState(() {
      _lockedUntil = lockedUntil;
      _error = lockedUntil == null
          ? null
          : AppLocalizations.of(context)
              .pinLockScreenLockedOut(TimeOfDay.fromDateTime(lockedUntil.toLocal())
                  .format(context));
    });
    if (lockedUntil == null) return;
    final remaining = lockedUntil.difference(DateTime.now());
    if (remaining.isNegative) return;
    _countdownTimer = Timer(remaining + const Duration(seconds: 1), () {
      if (mounted) setState(() => _error = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locked = _isLockedOut;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.pinLockScreenPrompt, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('pin-unlock-field'),
          controller: _pinController,
          focusNode: _focusNode,
          autofocus: true,
          enabled: !_submitting && !locked,
          obscureText: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 8,
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          InlineError(key: const ValueKey('pin-unlock-error'), message: _error!),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('pin-unlock-button'),
          onPressed: _submitting || locked ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.pinLockScreenUnlockButton),
        ),
      ],
    );
  }
}
