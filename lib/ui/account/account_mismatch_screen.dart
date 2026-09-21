/// Wrong account on a bound device (U6; R15, F7, AE5). The engine refuses
/// to run; this screen explains why (naming the Apple "Hide My Email"
/// case and the different-Google-account case, #2 U5; R11, AE7) and
/// offers the non-destructive exit first: "Switch account" is
/// `signOut(scope: local)` and nothing else — the data stays. "Remove this
/// device's data" is the one destructive path (`resetDevice`, KTD16),
/// behind a confirmation.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show RemovePushRegistrationCallback;
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/device_reset_callback.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/destructive_button.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/theme/tokens.dart';
import 'package:provider/provider.dart';

class AccountMismatchScreen extends StatefulWidget {
  const AccountMismatchScreen({super.key});

  @override
  State<AccountMismatchScreen> createState() => _AccountMismatchScreenState();
}

class _AccountMismatchScreenState extends State<AccountMismatchScreen> {
  bool _busy = false;
  String? _error;
  VoidCallback? _retry;

  Future<void> _switchAccount() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
    });
    final auth = context.read<AuthController>();
    try {
      // #1 (review fix): remove this device's push registration while the
      // session is still authenticated, before signOut() clears it - see
      // RemovePushRegistrationCallback's doc comment.
      await context.read<RemovePushRegistrationCallback?>()?.call();
      await auth.signOut(scope: AuthSignOutScope.local);
    } on AuthFailure catch (failure) {
      // The local session is gone regardless (service contract).
      debugPrint('lunarlog auth: switch-account sign-out reported $failure');
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).accountMismatchSwitchError;
          _retry = _switchAccount;
        });
      }
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
        title: Text(
          AppLocalizations.of(dialogContext).accountMismatchRemoveDialogTitle,
        ),
        content: SingleChildScrollView(
          child: Text(
            AppLocalizations.of(dialogContext).accountMismatchRemoveDialogBody,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              AppLocalizations.of(dialogContext).accountMismatchCancel,
            ),
          ),
          DestructiveButton(
            key: const ValueKey('mismatch-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              AppLocalizations.of(dialogContext).accountMismatchRemoveConfirm,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
    });
    try {
      await reset();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).accountMismatchRemoveError;
          _retry = _removeData;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Provider.of<AuthController?>(context)?.currentUser?.email;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountMismatchTitle),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            email == null
                ? l10n.accountMismatchBodyNoEmail
                : l10n.accountMismatchBodyWithEmail(email),
          ),
          const SizedBox(height: 12),
          Text(l10n.accountMismatchExplainer),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('mismatch-switch-account'),
            onPressed: _busy ? null : _switchAccount,
            child: Text(l10n.accountMismatchSwitchAccount),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.accountMismatchSwitchAccountSubtitle,
            style: LLType.bodySmall.toTextStyle(),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('mismatch-remove-data'),
            onPressed: _busy ? null : _removeData,
            child: Text(l10n.accountMismatchRemoveData),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            InlineError(
              key: const ValueKey('mismatch-error'),
              message: _error!,
              onRetry: _busy ? null : _retry,
            ),
          ],
        ],
      ),
    );
  }
}
