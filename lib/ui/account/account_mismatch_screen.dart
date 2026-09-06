/// Wrong account on a bound device (U6; R15, F7, AE5). The engine refuses
/// to run; this screen explains why (naming the Apple "Hide My Email"
/// case and the different-Google-account case, #2 U5; R11, AE7) and
/// offers the non-destructive exit first: "Switch account" is
/// `signOut(scope: local)` and nothing else — the data stays. "Remove this
/// device's data" is the one destructive path (`resetDevice`, KTD16),
/// behind a confirmation.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart' show DeviceResetCallback;
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:provider/provider.dart';

class AccountMismatchScreen extends StatefulWidget {
  const AccountMismatchScreen({super.key});

  @override
  State<AccountMismatchScreen> createState() => _AccountMismatchScreenState();
}

class _AccountMismatchScreenState extends State<AccountMismatchScreen> {
  bool _busy = false;

  Future<void> _switchAccount() async {
    if (_busy) return;
    setState(() => _busy = true);
    final auth = context.read<AuthController>();
    try {
      await auth.signOut(scope: AuthSignOutScope.local);
    } on AuthFailure catch (failure) {
      // The local session is gone regardless (service contract).
      debugPrint('lunarlog auth: switch-account sign-out reported $failure');
    } finally {
      // The local session ends here regardless of the service's answer
      // (see the comment above), so this is a real session-ending path —
      // same as resetDevice (KTD16) — and breadcrumbs recorded under the
      // account being left must not ride into a ticket filed by whoever
      // signs in next on a shared device.
      defaultBreadcrumbLog.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeData() async {
    if (_busy) return;
    final reset = context.read<DeviceResetCallback?>();
    if (reset == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: kRouteAccountMismatchDialog),
      builder: (dialogContext) => AlertDialog(
        title: const Text("Remove this device's data?"),
        content: const Text(
          'Erases every profile and entry stored on this device and signs '
          'out. The data stays in the account it belongs to; it is not '
          'deleted there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('mismatch-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove and sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await reset();
  }

  @override
  Widget build(BuildContext context) {
    final email = Provider.of<AuthController?>(context)?.currentUser?.email;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Different account'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            email == null
                ? 'This device holds data that belongs to a different account '
                    'than the one you just signed in to.'
                : 'This device holds data that belongs to a different account '
                    'than $email.',
          ),
          const SizedBox(height: 12),
          const Text(
            'This device is set up for a different account. This happens '
            "when Apple's Hide My Email created a new account, or when you "
            'chose a different Google account. Nothing has been uploaded or '
            'changed.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('mismatch-switch-account'),
            onPressed: _busy ? null : _switchAccount,
            child: const Text('Switch account'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Signs out and keeps everything on this device.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('mismatch-remove-data'),
            onPressed: _busy ? null : _removeData,
            child: const Text("Remove this device's data"),
          ),
        ],
      ),
    );
  }
}
