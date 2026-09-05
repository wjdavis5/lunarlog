/// Settings "Account" section (U6; R6, R16, AS3, F6). Rendered only when
/// an [AuthController] is provided (an unconfigured build has none, so
/// the section is absent, KTD11). Tiles: sign in / signed-in email, the
/// sync status tile, "Sync now", "Export data" (U1; R13), "Sign out",
/// "Sign out everywhere", and "Delete account" (U1; R14). Both sign-outs
/// end in the one device reset (KTD16); the plain one warns
/// first when unsynced rows (tombstones included) exist.
///
/// Export (U1; R13): "Export data" builds CSV, a one-page PDF summary, and
/// JSON for the selected profile through the system share sheet; temp files
/// are deleted whatever the share reports.
///
/// Deletion (U1; R14): "Delete account" offers the export first
/// (non-blocking, skippable), requires a typed DELETE confirmation, runs
/// the server cascade online (an offline attempt refuses and removes
/// nothing), revokes the Apple token on a best-effort basis, and ends in
/// the one device reset to first-run.
///
/// Sign-in methods and adding one (#2 U5; KTD5, R9, R10, F5): the
/// identity tile's subtitle lists the account's methods from
/// [AuthUser.providers]; "Add Google" (`account-add-google`, only when the
/// build has Google and the method is absent) and "Add Apple"
/// (`account-add-apple`, iOS only, same rule) first run
/// [GateController.reauthenticate] — a declined or unavailable device
/// credential cancels silently with no provider call and no copy, like a
/// dismissed picker — then link through the controller with the tapped
/// tile disabled behind a spinner. Both steps run inside one
/// [GateController.duringSystemUi] window (#65 U2; KTD4, KTD6), so
/// neither the credential prompt nor the provider picker re-locks the app
/// on the way through. Success
/// re-reads `currentUser.providers` in `setState` (a same-state
/// `userUpdated` does not notify); a failure renders its generic copy in
/// `account-link-error` beneath the identity tile (R14).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show DeviceResetCallback, GateController;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/account/account_deletion.dart';
import 'package:lunarlog/data/account/apple_revocation.dart';
import 'package:lunarlog/data/account/supabase_account_deletion.dart';
import 'package:lunarlog/data/export/export_service.dart';
import 'package:lunarlog/data/export/share_client.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

const String kSignOutConsequenceCopy =
    'This removes the data from this device. It stays in your account.';

/// Human label for a Supabase identity provider id (#2 U5; R9). Known ids
/// map to their brand names; anything else is capitalized as-is.
String providerLabel(String provider) => switch (provider) {
      AuthProviders.email => 'Email',
      AuthProviders.google => 'Google',
      AuthProviders.apple => 'Apple',
      '' => '',
      _ => provider[0].toUpperCase() + provider.substring(1),
    };

/// Kinds-only copy for an export failure (R18: no paths, no content).
String accountExportCopy(ExportError error) => switch (error) {
      ExportNoProfileError() => 'That profile no longer exists.',
      ExportIoError() => 'Export failed. Nothing was shared.',
      ExportShareFailedError() => 'Sharing failed. Nothing was shared.',
    };

/// Kinds-only copy for a deletion failure (R18). Every copy states what
/// was (not) removed.
String accountDeletionCopy(AccountDeletionError error) => switch (error) {
      AccountDeletionOfflineError() =>
        'No connection. Nothing was deleted.',
      AccountDeletionNotSignedInError() =>
        'You are signed out. Nothing was deleted.',
      AccountDeletionServerError() =>
        'Deletion failed. Nothing on this device was removed.',
    };

class AccountSection extends StatefulWidget {
  const AccountSection({
    super.key,
    this.showAddGoogle,
    this.showAddApple,
    this.exportService,
    this.deleteServerData,
    this.revokeAppleToken,
  });

  /// Whether "Add Google" may render; null means [AppConfig.hasGoogle]
  /// (#2 U5). Injectable so tests exercise the action without defines.
  final bool? showAddGoogle;

  /// Whether "Add Apple" may render; null means "iOS, not web" (#2 U5).
  final bool? showAddApple;

  /// Export delivery; null builds one from the context's repositories with
  /// the system share sheet (U1; R13). Injectable for tests.
  final ExportService? exportService;

  /// The privileged server cascade; null runs `request_account_deletion`
  /// over the configured client (U1; R14). Injectable for tests.
  final DeleteServerData? deleteServerData;

  /// Best-effort Apple token revocation; null uses the documented no-op
  /// seam. Injectable for tests.
  final RevokeAppleToken? revokeAppleToken;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  /// The provider whose link call is in flight, or null. One action at a
  /// time: the tapped tile is disabled and a second tap does nothing.
  String? _linking;
  String? _linkError;

  /// True while an export or a deletion is running; both tiles are
  /// disabled meanwhile.
  bool _busy = false;

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
    final user = auth.currentUser;
    final providers = user?.providers ?? const <String>[];
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
            title: Text(user?.email == null
                ? 'Signed in'
                : 'Signed in as ${user!.email}'),
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
          if (_canAddApple && !providers.contains(AuthProviders.apple))
            _addMethodTile(
              key: 'account-add-apple',
              provider: AuthProviders.apple,
              icon: Icons.apple,
              label: 'Add Apple',
              onTap: () => _addMethod(AuthProviders.apple, auth.linkApple),
            ),
          if (_canAddGoogle && !providers.contains(AuthProviders.google))
            _addMethodTile(
              key: 'account-add-google',
              provider: AuthProviders.google,
              icon: Icons.add_link,
              label: 'Add Google',
              onTap: () => _addMethod(AuthProviders.google, auth.linkGoogle),
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
            onTap: _busy ? null : () => _signOut(context),
          ),
          ListTile(
            key: const ValueKey('account-sign-out-everywhere'),
            leading: const Icon(Icons.devices_other),
            title: const Text('Sign out everywhere'),
            subtitle: const Text('Ends every session of this account.'),
            onTap: _busy ? null : () => _signOutEverywhere(context),
          ),
          ListTile(
            key: const ValueKey('account-export'),
            leading: const Icon(Icons.download),
            title: const Text('Export data'),
            subtitle:
                const Text('CSV, PDF summary, and JSON for one profile.'),
            onTap: _busy ? null : () => _export(context),
          ),
          ListTile(
            key: const ValueKey('account-delete'),
            leading: Icon(Icons.delete_forever,
                color: theme.colorScheme.error),
            title: Text('Delete account',
                style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text(
                'Deletes your account and its data everywhere.'),
            onTap: _busy ? null : () => _deleteAccount(context),
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
  /// the controller. A declined credential cancels with no provider call
  /// and no copy.
  ///
  /// Both ceremonies run inside one system-UI window (#65 U2; KTD6) — the
  /// credential prompt nests its own inside it, which the window's depth
  /// counter handles — so neither the prompt nor the picker re-locks the
  /// app on the way through.
  Future<void> _addMethod(
      String provider, Future<AuthUser> Function() link) async {
    if (_linking != null) return;
    final gate = context.read<GateController?>();
    if (gate == null) {
      debugPrint('lunarlog account: no gate to re-authenticate with');
      return;
    }
    setState(() => _linkError = null);
    await gate
        .duringSystemUi(() => _reauthenticateAndLink(gate, provider, link));
  }

  Future<void> _reauthenticateAndLink(GateController gate, String provider,
      Future<AuthUser> Function() link) async {
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
      await _reset(context);
      return;
    }
    if (!context.mounted) return;
    await _reset(context);
  }

  ExportService _services(BuildContext context) =>
      widget.exportService ??
      ExportService(
        profiles: context.read<ProfilesRepository>(),
        dayEntries: context.read<DayEntriesRepository>(),
        tempDirectory: getTemporaryDirectory,
        shareFiles: shareExportFiles,
      );

  DeleteServerData _cascade() =>
      widget.deleteServerData ?? _supabaseCascade;

  /// The production cascade: `request_account_deletion` over the
  /// configured client. Without a configured backend there is no account
  /// to delete, so the attempt fails closed as a server error.
  Future<void> _supabaseCascade() {
    if (!AppConfig.hasSupabase) {
      throw const AccountDeletionError.server();
    }
    return SupabaseAccountDeletion(Supabase.instance.client)
        .deleteServerData();
  }

  void _snack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
  }

  /// U1 (R13): shares CSV, PDF summary, and JSON for one profile. Returns
  /// true when the share sheet was shown.
  Future<bool> _export(BuildContext context) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      return await _runExport(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Profile picker for export and deletion flows. Null means cancelled.
  Future<String?> _pickProfile(
      BuildContext context, List<Profile> profiles) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const ValueKey('account-export-pick'),
        title: const Text('Export which profile?'),
        children: [
          for (final profile in profiles)
            SimpleDialogOption(
              key: ValueKey('account-export-pick-${profile.id}'),
              onPressed: () => Navigator.of(dialogContext).pop(profile.id),
              child: Text(profile.displayName),
            ),
        ],
      ),
    );
  }

  /// U1 (R14): export-first offer (non-blocking, skippable), typed DELETE
  /// confirmation, online cascade, best-effort Apple revocation, then the
  /// one device reset to first-run.
  Future<void> _deleteAccount(BuildContext context) async {
    if (_busy) return;
    final auth = context.read<AuthController>();
    final user = auth.currentUser;
    final signedIn = auth.state == AuthSessionState.signedIn ||
        auth.state == AuthSessionState.passwordRecovery;
    setState(() => _busy = true);
    try {
      final offer = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('account-delete-export-offer'),
          title: const Text('Keep a copy first?'),
          content: const Text(
            'Export builds CSV, a PDF summary, and JSON for one profile '
            'through the share sheet. You can skip and delete right away.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('account-delete-export-skip'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              key: const ValueKey('account-delete-export-go'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Export a profile'),
            ),
          ],
        ),
      );
      if (offer == null || !context.mounted) return;
      // Non-blocking: an export failure reports its own copy and the
      // deletion still proceeds to confirmation.
      if (offer) await _runExport(context);

      if (!context.mounted) return;
      final confirmed = await _confirmDeletion(context);
      if (confirmed != true || !context.mounted) return;

      final service = AccountDeletionService(
        deleteServerData: _cascade(),
        revokeAppleToken:
            widget.revokeAppleToken ?? revokeAppleTokenBestEffort,
        resetDevice: () => _reset(context),
      );
      try {
        await service.deleteAccount(
          signedIn: signedIn,
          providers: user?.providers ?? const <String>[],
        );
      } on AccountDeletionError catch (error) {
        if (!context.mounted) return;
        _snack(context, accountDeletionCopy(error));
      }
      // On success the reset unmounted this tree; nothing to report.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The export body shared by [_export] and the deletion's non-blocking
  /// first step ([_deleteAccount] holds `_busy` throughout, so this never
  /// touches it).
  Future<bool> _runExport(BuildContext context) async {
    final service = _services(context);
    final profilesRepo = context.read<ProfilesRepository>();
    try {
      final profiles = await profilesRepo.list();
      if (!context.mounted) return false;
      if (profiles.isEmpty) {
        _snack(context, 'Nothing to export yet.');
        return false;
      }
      final profileId = profiles.length == 1
          ? profiles.single.id
          : await _pickProfile(context, profiles);
      if (profileId == null || !context.mounted) return false;
      try {
        await service.exportProfile(profileId);
      } on ExportError catch (error) {
        if (!context.mounted) return false;
        _snack(context, accountExportCopy(error));
        return false;
      }
      if (!context.mounted) return false;
      _snack(context, 'Export shared.');
      return true;
    } catch (error) {
      debugPrint('lunarlog account: export failed (${error.runtimeType})');
      if (context.mounted) {
        _snack(context,
            accountExportCopy(const ExportError.shareFailed()));
      }
      return false;
    }
  }

  /// Typed DELETE confirmation. Null means cancelled.
  Future<bool?> _confirmDeletion(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteConfirmDialog(
        controller: controller,
      ),
    ).whenComplete(controller.dispose);
  }
}

/// Typed-confirmation dialog for account deletion (U1; R14). The delete
/// button enables only when the field reads DELETE exactly.
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({required this.controller});

  final TextEditingController controller;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('account-delete-confirm'),
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This deletes your account and its data on the server and on '
            'this device. Type DELETE to confirm.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('account-delete-confirm-field'),
            controller: widget.controller,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Type DELETE',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('account-delete-confirm-delete'),
          onPressed: widget.controller.text == 'DELETE'
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
