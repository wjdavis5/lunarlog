/// Bottom sheet presented when redeeming a prediction-only connection code
/// (issue #151) — the kind=prediction counterpart of `AcceptInviteSheet`.
///
/// The copy is explicit that this is a narrower grant than guardian
/// sharing: the recipient sees derived phases (period / fertile /
/// ovulation / PMS) on a read-only calendar and nothing else — no notes,
/// tags, or logs sync to this device.
library;

import 'package:flutter/material.dart';

import '../../domain/sharing/prediction_connection_service.dart';

class AcceptPredictionConnectionSheet extends StatefulWidget {
  const AcceptPredictionConnectionSheet({
    super.key,
    required this.rawToken,
    required this.service,
    this.onAccepted,
  });

  final String rawToken;
  final PredictionConnectionService service;

  /// Called with the accepted connection before the sheet pops (the app
  /// shell pushes the phase calendar with it).
  final void Function(AcceptedPredictionConnection result)? onAccepted;

  @override
  State<AcceptPredictionConnectionSheet> createState() =>
      _AcceptPredictionConnectionSheetState();
}

class _AcceptPredictionConnectionSheetState
    extends State<AcceptPredictionConnectionSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.service.acceptConnection(
        rawToken: widget.rawToken,
      );
      if (mounted) {
        // Pop this sheet's own route *before* invoking the callback:
        // [onAccepted] (the app shell's `_showPredictionConnectionSheet`)
        // pushes the phase calendar onto the same Navigator this sheet
        // lives on. Popping after the push would pop whatever is now on
        // top of the stack -- the just-pushed calendar, not this sheet --
        // leaving the sheet stuck open and the push/pop transitions
        // fighting each other (observed as `pumpAndSettle` never
        // settling). Popping first leaves a clean single push behind it.
        Navigator.of(context).pop(result);
        widget.onAccepted?.call(result);
      }
    } on PredictionConnectionFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = failure.userFacingMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'An unexpected error occurred.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_month,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connect to cycle predictions',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Accepting adds a read-only calendar of their estimated '
              'period, fertile, ovulation, and PMS days. No notes, tags, '
              'or logs are ever shared or synced to this device.',
              style: TextStyle(height: 1.35),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _accept,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
