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
///
/// Export and delete (Issue #17 U6; R1-R3, R6, R10, R11): "Export my data"
/// (`account-export`) and "Delete account" (`account-delete`, destructive)
/// render only when `signedIn`; delete additionally needs an
/// [AccountDeletionService] (R11). Deletion runs a fresh device credential
/// check first (`gate.duringSystemUi(gate.reauthenticate)`, mirroring the
/// add-method ceremony, KTD7) - a decline cancels silently (AE5) - then the
/// confirmation naming the server rows, the account, and this device's data
/// (R2), then, only when the account has an Apple identity, a *second*
/// system-UI window around a fresh Apple authorization-code fetch (KTD3) -
/// a cancelled Apple sheet also cancels silently - then the service call,
/// then the one device reset (`_reset`, KTD16). No reset runs on any
/// failure (R12); each [AccountDeletionFailure] renders its own copy in
/// `account-delete-error`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show DeviceResetCallback, GateController;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/export/account_export_writer.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/delete_account_dialog.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// The app's version string as carried into an export document (Issue #17
/// U5/U6). Kept in step with `pubspec.yaml`'s `version:` by hand - `lib/ui`
/// must not read it from a plugin (KTD6 keeps that off the pure builder,
/// and there is no reason to add the dependency just for this one string).
const String kAppVersionForExport = '1.0.0+1';

/// Generic, provider-free copy per [AccountDeletionFailure] kind (Issue #17
/// U6; R10), the same shape as [authFailureCopy]. [AccountDeletionFailure
/// .appleRevokeFailed] gets a distinct line: the server rows are already
/// gone, but the account itself was deliberately left intact and the whole
/// call is safe to retry (#17 KTD4).
String accountDeletionFailureCopy(AccountDeletionFailure failure) =>
    switch (failure) {
      AccountDeletionNetworkFailure() =>
        'Could not reach the server. Check your connection and try again. '
            'Your account was not deleted.',
      AccountDeletionUnauthorizedFailure() =>
        'Your session has expired. Sign in again and retry - your account '
            'was not deleted.',
      AccountDeletionAppleRevokeFailedFailure() =>
        'Your account data was deleted, but Apple could not confirm the '
            'sign-in revocation, so your account sign-in itself still '
            'exists. Try again to finish removing it, or contact support if '
            'you\'re concerned about the lingering Apple access.',
      AccountDeletionTimeoutFailure() =>
        'This is taking longer than expected and we can\'t confirm whether '
            'your account was deleted. Wait a moment and check whether '
            'you\'re still signed in before retrying - retrying is safe '
            'either way.',
      AccountDeletionDeleteUserFailedFailure() =>
        'Your account data has already been deleted, but removing the '
            'account sign-in itself did not finish. Please try again in a '
            'moment, or contact support if it keeps failing.',
      AccountDeletionUnknownFailure() =>
        'Something went wrong. Your account was not deleted. Please try '
            'again.',
    };

/// One line, no email/token/exception text (Issue #17 U6; R10).
const String kAccountExportFailureCopy =
    'Could not export your data. Please try again.';

/// The action currently in flight in [AccountSection], if any - one at a
/// time (R11's spinner rule extended to export/delete).
enum _AccountAction { export, delete }

/// Injectable seam for the export step (Issue #17 U5/U6): the default
/// builds the real platform writer; tests substitute a fake that just
/// records the call (or throws) without touching `path_provider`/
/// `share_plus`.
typedef ExportAccountCollaborator = Future<void> Function({
  required List<Profile> profiles,
  required Map<String, List<DayEntry>> entriesByProfile,
  required String appVersion,
});

Future<void> _defaultExportAccountCollaborator({
  required List<Profile> profiles,
  required Map<String, List<DayEntry>> entriesByProfile,
  required String appVersion,
}) =>
    const AccountExportWriter().exportAndShare(
      profiles: profiles,
      entriesByProfile: entriesByProfile,
      appVersion: appVersion,
    );

/// Injectable seam for the Apple authorization-code fetch (Issue #17 U6;
/// KTD3): the default calls the real native dialog with no scopes (only
/// the `authorizationCode` is needed for revocation - not an email or full
/// name); tests substitute a fake and never touch the platform channel.
typedef AppleAuthorizationCodeRequest = Future<AuthorizationCredentialAppleID>
    Function();

Future<AuthorizationCredentialAppleID> _defaultAppleAuthorizationCodeRequest() =>
    SignInWithApple.getAppleIDCredential(scopes: const []);

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

class AccountSection extends StatefulWidget {
  const AccountSection({
    super.key,
    this.showAddGoogle,
    this.showAddApple,
    this.showExportAndDelete,
    this.exportAccount,
    this.appleAuthorizationCodeRequest,
  });

  /// Whether "Add Google" may render; null means [AppConfig.hasGoogle]
  /// (#2 U5). Injectable so tests exercise the action without defines.
  final bool? showAddGoogle;

  /// Whether "Add Apple" may render; null means "iOS, not web" (#2 U5).
  final bool? showAddApple;

  /// Whether "Export my data" and "Delete account" may render at all; null
  /// means "not web" (Issue #17 R11 - neither tile ships on web, regardless
  /// of `LUNARLOG_WEB_SYNC`). Injectable so tests simulate web without
  /// actually running on it.
  final bool? showExportAndDelete;

  /// Export collaborator (Issue #17 U5/U6); null means
  /// [_defaultExportAccountCollaborator] (the real platform writer).
  /// Injectable so tests never touch `path_provider`/`share_plus`.
  final ExportAccountCollaborator? exportAccount;

  /// Apple authorization-code fetch (Issue #17 U6; KTD3); null means
  /// [_defaultAppleAuthorizationCodeRequest]. Injectable so tests never
  /// touch the platform channel.
  final AppleAuthorizationCodeRequest? appleAuthorizationCodeRequest;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  /// The provider whose link call is in flight, or null. One action at a
  /// time: the tapped tile is disabled and a second tap does nothing.
  String? _linking;
  String? _linkError;

  /// Export/delete's shared busy flag (Issue #17 U6): one of those two
  /// actions at a time, independent of [_linking].
  _AccountAction? _action;
  String? _exportError;
  String? _deleteError;

  bool get _canAddGoogle => widget.showAddGoogle ?? AppConfig.hasGoogle;

  bool get _canAddApple =>
      widget.showAddApple ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  bool get _canExportAndDelete => widget.showExportAndDelete ?? !kIsWeb;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthController?>(context);
    if (auth == null) return const SizedBox.shrink();
    final sync = Provider.of<SyncStatusController?>(context);
    final deletionService = Provider.of<AccountDeletionService?>(context);
    final signedIn = auth.state == AuthSessionState.signedIn ||
        auth.state == AuthSessionState.passwordRecovery;
    final theme = Theme.of(context);
    final user = auth.currentUser;
    final providers = user?.providers ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Account', style: theme.textTheme.titleSmall),
        ),
        if (signedIn)
          ..._buildSignedInIdentityTiles(auth, user, providers, theme)
        else
          _buildSignInTile(context, auth),
        const SyncStatusTile(),
        if (signedIn && sync != null) _buildSyncNowTile(sync),
        if (signedIn) ..._buildSignOutTiles(context),
        if (signedIn && _canExportAndDelete)
          ..._buildExportAndDeleteTiles(
              context, theme, deletionService, providers),
      ],
    );
  }

  /// The identity tile, any link-failure copy, and the "Add Apple"/"Add
  /// Google" tiles for a signed-in operator.
  List<Widget> _buildSignedInIdentityTiles(
    AuthController auth,
    AuthUser? user,
    List<String> providers,
    ThemeData theme,
  ) {
    final linkError = _linkError;
    return [
      ListTile(
        key: const ValueKey('account-identity'),
        leading: const Icon(Icons.person_outline),
        title: Text(
            user?.email == null ? 'Signed in' : 'Signed in as ${user!.email}'),
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
    ];
  }

  Widget _buildSignInTile(BuildContext context, AuthController auth) {
    return ListTile(
      key: const ValueKey('account-sign-in'),
      leading: const Icon(Icons.login),
      title: Text(
          auth.state == AuthSessionState.expired ? 'Sign in again' : 'Sign in'),
      subtitle: const Text('Sync this device\'s data to an account.'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
      ),
    );
  }

  Widget _buildSyncNowTile(SyncStatusController sync) {
    return ListTile(
      key: const ValueKey('account-sync-now'),
      leading: const Icon(Icons.sync),
      title: const Text('Sync now'),
      enabled: !isSyncRunning(sync.snapshot),
      onTap: sync.requestSync,
    );
  }

  List<Widget> _buildSignOutTiles(BuildContext context) {
    return [
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
    ];
  }

  /// The export/delete tiles and their inline error copy (Issue #17 U6).
  List<Widget> _buildExportAndDeleteTiles(
    BuildContext context,
    ThemeData theme,
    AccountDeletionService? deletionService,
    List<String> providers,
  ) {
    return [
      ListTile(
        key: const ValueKey('account-export'),
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('Export my data'),
        subtitle: const Text(
            'Save your profiles and day entries as a JSON file.'),
        enabled: _action == null,
        trailing: _action == _AccountAction.export
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: _action == null ? () => _exportAccount(context) : null,
      ),
      if (_exportError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _exportError!,
            key: const ValueKey('account-export-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      if (deletionService != null)
        ListTile(
          key: const ValueKey('account-delete'),
          leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
          title: Text('Delete account',
              style: TextStyle(color: theme.colorScheme.error)),
          subtitle: const Text(
              'Removes the account, its server rows, and this device\'s data.'),
          enabled: _action == null,
          trailing: _action == _AccountAction.delete
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _action == null
              ? () => _deleteAccount(context, providers)
              : null,
        ),
      if (_deleteError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _deleteError!,
            key: const ValueKey('account-delete-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
    ];
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
  ///
  /// [reset] may be passed in already resolved (Issue #17 P1 fix) for a
  /// caller that must read it from [context] *before* an async gap, so the
  /// actual data-wipe side effect still runs even if [context] is
  /// unmounted by the time this is called - only the UI navigation step is
  /// gated on [BuildContext.mounted].
  Future<void> _reset(BuildContext context, {DeviceResetCallback? reset}) async {
    final resetCallback = reset ?? context.read<DeviceResetCallback?>();
    if (resetCallback == null) {
      debugPrint('lunarlog account: no device reset available');
      return;
    }
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    await resetCallback();
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

  /// Collects this device's profiles and their entries and hands them to
  /// the export collaborator (Issue #17 U5/U6; KTD5). Does not catch: the
  /// two callers (the standalone tile and the delete dialog's "Export
  /// first") each render the failure their own way.
  Future<void> _runExport(BuildContext context) async {
    final profilesRepo = context.read<ProfilesRepository>();
    final entriesRepo = context.read<DayEntriesRepository>();
    final profiles = await profilesRepo.list();
    final entriesByProfile = <String, List<DayEntry>>{};
    for (final profile in profiles) {
      entriesByProfile[profile.id] =
          await entriesRepo.listForProfile(profile.id);
    }
    await (widget.exportAccount ?? _defaultExportAccountCollaborator)(
      profiles: profiles,
      entriesByProfile: entriesByProfile,
      appVersion: kAppVersionForExport,
    );
  }

  /// "Export my data" (R8): one action at a time, failures render as copy
  /// beneath the tile rather than an exception (AE4, R10).
  Future<void> _exportAccount(BuildContext context) async {
    if (_action != null) return;
    setState(() {
      _action = _AccountAction.export;
      _exportError = null;
    });
    try {
      await _runExport(context);
    } catch (error) {
      debugPrint('lunarlog account: export failed (${error.runtimeType})');
      if (mounted) setState(() => _exportError = kAccountExportFailureCopy);
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  /// Delete flow (Issue #17 U6; R1-R3, R6, R12, KTD7). In order: a fresh
  /// device credential (declining cancels silently, AE5); the confirmation
  /// naming server rows, the account, and this device's data, with
  /// "Export first" available without proceeding (R2); when the account
  /// has an Apple identity, a fresh authorization code (a cancelled Apple
  /// sheet also cancels silently, KTD3); the service call; then the one
  /// device reset (KTD16). No reset runs on any failure (R12).
  Future<void> _deleteAccount(
      BuildContext context, List<String> providers) async {
    if (_action != null) return;
    final gate = context.read<GateController?>();
    if (gate == null) {
      debugPrint('lunarlog account: no gate to re-authenticate with');
      return;
    }
    setState(() => _deleteError = null);
    final granted = await gate.duringSystemUi(gate.reauthenticate);
    if (!granted || !context.mounted) return;

    final decision = await showDeleteAccountDialog(
      context,
      onExport: () => _runExport(context),
    );
    if (decision != DeleteAccountDecision.delete || !context.mounted) return;

    final service = context.read<AccountDeletionService?>();
    if (service == null) {
      debugPrint('lunarlog account: no deletion service configured');
      return;
    }

    await _performDeletion(context, gate, service, providers);
  }

  /// The service call itself, once the credential and confirmation steps
  /// have passed: a fresh Apple authorization code first when the account
  /// carries an Apple identity (a cancelled Apple sheet aborts silently,
  /// KTD3), then the deletion call, then the one device reset (R6, KTD16).
  /// No reset runs on any failure (R12).
  ///
  /// The device reset callback is read from [context] *before* any `await`
  /// below (Issue #17 P1 fix): a confirmed successful deletion must still
  /// wipe this device's local data even if the Settings screen (and this
  /// widget) has since been navigated away from or otherwise unmounted -
  /// skipping the wipe would leave a deleted account's data sitting on
  /// disk. Only the UI feedback (`setState`, the pop in [_reset]) stays
  /// gated on [mounted]/`context.mounted`.
  Future<void> _performDeletion(
    BuildContext context,
    GateController gate,
    AccountDeletionService service,
    List<String> providers,
  ) async {
    final resetCallback = context.read<DeviceResetCallback?>();
    setState(() => _action = _AccountAction.delete);
    try {
      String? appleCode;
      if (providers.contains(AuthProviders.apple)) {
        appleCode = await gate.duringSystemUi(_fetchAppleAuthorizationCode);
        if (appleCode == null) return; // cancelled Apple sheet: silent abort
      }
      await service.deleteAccount(appleAuthorizationCode: appleCode);
    } on AccountDeletionFailure catch (failure) {
      if (mounted) {
        setState(() => _deleteError = accountDeletionFailureCopy(failure));
      }
      return;
    } catch (error) {
      debugPrint('lunarlog account: delete failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _deleteError =
            accountDeletionFailureCopy(const AccountDeletionFailure.unknown()));
      }
      return;
    } finally {
      if (mounted) setState(() => _action = null);
    }
    // context is intentionally used here whether or not it is still mounted
    // (Issue #17 P1 fix): _reset only ever uses it for the UI pop, gated on
    // context.mounted internally, and always calls resetCallback (the data
    // wipe) regardless.
    // ignore: use_build_context_synchronously
    await _reset(context, reset: resetCallback);
  }

  /// A fresh Sign in with Apple authorization code (#17 KTD3). Null means
  /// the operator cancelled the sheet; the caller treats that like a
  /// declined credential (silent abort, no copy). Any other Apple error
  /// propagates - the caller's generic catch surfaces it as
  /// [AccountDeletionFailure.unknown] copy rather than doing nothing, so a
  /// genuine failure (e.g. misconfiguration) is never mistaken for a
  /// dismissed sheet.
  Future<String?> _fetchAppleAuthorizationCode() async {
    try {
      final credential = await (widget.appleAuthorizationCodeRequest ??
          _defaultAppleAuthorizationCodeRequest)();
      return credential.authorizationCode;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }
}
