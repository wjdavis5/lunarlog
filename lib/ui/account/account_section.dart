/// Settings "Account" section (U6; R6, R16, AS3, F6). Rendered only when
/// an [AuthController] is provided (an unconfigured build has none, so
/// the section is absent, KTD11). Tiles: sign in / signed-in email, the
/// sync status tile, "Sync now", "Sign out" and "Sign out everywhere".
/// Both sign-outs end in the one device reset (KTD16); the plain one warns
/// first when unsynced rows (tombstones included) exist.
///
/// Sign-in methods and adding one (#2 U5; KTD5, R9, R10, F5): the
/// identity tile's subtitle lists the account's methods from
/// [AuthUser.providers]; "Add Google" (`account-add-google`, only when the
/// build has Google and the method is absent) and "Add Apple"
/// (`account-add-apple`, iOS only, same rule) first run
/// [GateController.reauthenticate] — a declined, unavailable, or
/// interrupted device credential cancels silently with no provider call
/// and no copy, like a dismissed picker — then link through the
/// controller with the tapped tile disabled behind a spinner. Success
/// re-reads `currentUser.providers` in `setState` (a same-state
/// `userUpdated` does not notify); a failure renders its generic copy in
/// `account-link-error` beneath the identity tile (R14).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show DeviceResetCallback, GateController;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:provider/provider.dart';

const String kSignOutConsequenceCopy =
    'This removes the data from this device. It stays in your account.';

/// Human label for a Supabase identity provider id (#2 U5; R9). Known ids
/// map to their brand names; anything else is capitalized as-is.
String providerLabel(String provider) => switch (provider) {
      'email' => 'Email',
      'google' => 'Google',
      'apple' => 'Apple',
      '' => '',
      _ => provider[0].toUpperCase() + provider.substring(1),
    };

class AccountSection extends StatefulWidget {
  const AccountSection({super.key, this.showAddGoogle, this.showAddApple});

  /// Whether "Add Google" may render; null means [AppConfig.hasGoogle]
  /// (#2 U5). Injectable so tests exercise the action without defines.
  final bool? showAddGoogle;

  /// Whether "Add Apple" may render; null means "iOS, not web" (#2 U5).
  final bool? showAddApple;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  /// The provider whose link call is in flight, or null. One action at a
  /// time: the tapped tile is disabled and a second tap does nothing.
  String? _linking;
  String? _linkError;

  bool get _canAddGoogle => widget.showAddGoogle ?? AppConfig.hasGoogle;

  bool get _canAddApple =>
      widget.showAddApple ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthController?>(context);
    if (auth == null) return const SizedBox.shrink();
    final sync = Provider.of<SyncStatusController?>(context);
    final signedIn = auth.state == AuthSessionState.signedIn ||
        auth.state == AuthSessionState.passwordRecovery;
    final theme = Theme.of(context);
    final providers = auth.currentUser?.providers ?? const <String>[];
    final linkError = _linkError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Account', style: theme.textTheme.titleSmall),
        ),
        if (signedIn) ...[
          ListTile(
            key: const ValueKey('account-identity'),
            leading: const Icon(Icons.person_outline),
            title: Text(auth.currentUser?.email == null
                ? 'Signed in'
                : 'Signed in as ${auth.currentUser!.email}'),
            subtitle: providers.isEmpty
                ? null
                : Text('Sign-in methods: '
                    '${providers.map(providerLabel).join(', ')}'),
          ),
          if (linkError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                linkError,
                key: const ValueKey('account-link-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_canAddApple && !providers.contains('apple'))
            _addMethodTile(
              key: 'account-add-apple',
              provider: 'apple',
              icon: Icons.apple,
              label: 'Add Apple',
              onTap: () => _addMethod('apple', auth.linkApple),
            ),
          if (_canAddGoogle && !providers.contains('google'))
            _addMethodTile(
              key: 'account-add-google',
              provider: 'google',
              icon: Icons.add_link,
              label: 'Add Google',
              onTap: () => _addMethod('google', auth.linkGoogle),
            ),
        ] else
          ListTile(
            key: const ValueKey('account-sign-in'),
            leading: const Icon(Icons.login),
            title: Text(auth.state == AuthSessionState.expired
                ? 'Sign in again'
                : 'Sign in'),
            subtitle: const Text('Sync this device\'s data to an account.'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
            ),
          ),
        const SyncStatusTile(),
        if (signedIn && sync != null)
          ListTile(
            key: const ValueKey('account-sync-now'),
            leading: const Icon(Icons.sync),
            title: const Text('Sync now'),
            enabled: !isSyncRunning(sync.snapshot),
            onTap: sync.requestSync,
          ),
        if (signedIn) ...[
          ListTile(
            key: const ValueKey('account-sign-out'),
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: const Text('Removes the data from this device.'),
            onTap: () => _signOut(context),
          ),
          ListTile(
            key: const ValueKey('account-sign-out-everywhere'),
            leading: const Icon(Icons.devices_other),
            title: const Text('Sign out everywhere'),
            subtitle: const Text('Ends every session of this account.'),
            onTap: () => _signOutEverywhere(context),
          ),
        ],
      ],
    );
  }

  ListTile _addMethodTile({
    required String key,
    required String provider,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final busy = _linking == provider;
    return ListTile(
      key: ValueKey(key),
      leading: Icon(icon),
      title: Text(label),
      subtitle: const Text('Sign in to this account another way.'),
      enabled: _linking == null,
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _linking == null ? onTap : null,
    );
  }

  /// F5: device credential first (KTD5), then the provider picker through
  /// the controller. A declined or interrupted credential cancels with no
  /// provider call and no copy.
  Future<void> _addMethod(
      String provider, Future<AuthUser> Function() link) async {
    if (_linking != null) return;
    final gate = context.read<GateController?>();
    if (gate == null) {
      debugPrint('lunarlog account: no gate to re-authenticate with');
      return;
    }
    setState(() => _linkError = null);
    final granted = await gate.reauthenticate();
    if (!granted || !mounted) return;
    setState(() => _linking = provider);
    try {
      await link();
      // The controller does not notify on a same-state user update; the
      // rebuild below re-reads `currentUser.providers`.
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _linkError = authFailureCopy(failure));
    } catch (error) {
      debugPrint('lunarlog account: link failed (${error.runtimeType})');
      if (mounted) {
        setState(
            () => _linkError = authFailureCopy(const AuthFailure.unknown()));
      }
    } finally {
      if (mounted) setState(() => _linking = null);
    }
  }

  /// Runs the reset from the app's root route: the Settings route is
  /// popped first because the reset unmounts the whole tree beneath the
  /// root, and a pushed route would otherwise outlive its providers in
  /// harnesses that stub the reset.
  Future<void> _reset(BuildContext context) async {
    final reset = context.read<DeviceResetCallback?>();
    if (reset == null) {
      debugPrint('lunarlog account: no device reset available');
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    await reset();
  }

  Future<void> _signOut(BuildContext context) async {
    final sync = context.read<SyncStatusController?>();
    final dirty = sync?.snapshot.dirtyCount ?? 0;
    final bool? discard;
    if (dirty > 0) {
      discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unsynced changes'),
          content: Text(
            '$dirty ${dirty == 1 ? 'change' : 'changes'} on this device '
            '${dirty == 1 ? 'has' : 'have'} not been uploaded yet, '
            'deletions included. Sync first, or discard '
            '${dirty == 1 ? 'it' : 'them'} and sign out.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('account-sign-out-sync'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Sync now'),
            ),
            FilledButton(
              key: const ValueKey('account-sign-out-discard'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard unsynced changes and sign out'),
            ),
          ],
        ),
      );
      if (discard == false) {
        sync?.requestSync();
        return;
      }
    } else {
      discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(kSignOutConsequenceCopy),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('account-sign-out-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
    }
    if (discard != true || !context.mounted) return;
    await _reset(context);
  }

  Future<void> _signOutEverywhere(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out everywhere?'),
        content: const Text(
          'Ends every session of this account and removes the data from '
          'this device. Other devices may keep syncing for up to 10 minutes, '
          'until their access expires.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('account-sign-out-everywhere-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out everywhere'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final auth = context.read<AuthController>();
    try {
      await auth.signOut(scope: AuthSignOutScope.global);
    } on AuthFailure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${authFailureCopy(failure)} Other devices were not signed out.'),
      ));
      return;
    }
    if (!context.mounted) return;
    await _reset(context);
  }
}
