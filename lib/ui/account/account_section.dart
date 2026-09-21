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
/// credential calls no provider and renders the issue #984 line
/// (`accountReauthFailed`) rather than returning silently, which on a Face ID
/// loop was indistinguishable from a hang — then link through the controller
/// with the tapped tile disabled behind a spinner. Both steps run inside one
/// [GateController.duringSystemUi] window (#65 U2; KTD4, KTD6), so
/// neither the credential prompt nor the provider picker re-locks the app
/// on the way through. A link failure renders its generic copy in
/// `account-link-error` beneath the identity tile (R14).
///
/// Removing one (#31 U4; KTD6, KTD7, KTD8): "Remove Google"
/// (`account-remove-google`) / "Remove Apple" (`account-remove-apple`)
/// render whenever that method is present and the account holds at least
/// one other (`email` is never removable). Tapping shows a confirmation
/// dialog naming the consequence *before* the device-credential check —
/// unlike adding, removing is destructive — then the same
/// [GateController.duringSystemUi] ceremony and busy guard as adding,
/// tracked by the shared `_busyProvider` field so an add and a remove
/// cannot run at once. `auth.currentUser` already reflects the fresh
/// result of both directions' calls — [AuthController] adopts it itself
/// (#31 finding 2) — so this widget just re-reads `auth.currentUser`
/// after `await`ing; it does not track that state locally, which would
/// otherwise reset to stale on every Settings round trip (the section is
/// disposed and rebuilt each time `SettingsScreen` is popped and pushed
/// again).
///
/// Delete (Issue #17 U6; R1-R3, R6, R10, R11): "Delete account"
/// (`account-delete`, destructive) renders only when `signedIn` and an
/// [AccountDeletionService] is provided (R11). "Export my data" moved out
/// to `lib/ui/settings/your_data_section.dart` (Issue #222) - it no longer
/// needs an account, so it no longer lives in this sign-in-gated section;
/// this file keeps only the "Export first" affordance inside the delete
/// confirmation dialog below, wired through the same
/// [ExportAccountCollaborator] seam ([_runExport]) independently of that
/// other section. Deletion runs a fresh device credential
/// check first (`gate.duringSystemUi(gate.reauthenticate)`, mirroring the
/// add-method ceremony, KTD7) - a decline cancels silently (AE5) - then the
/// confirmation naming the server rows, the account, and this device's data
/// (R2), then the server-informed Apple flow (Issue #605/LLA-052; see
/// [_deleteAccountServerInformed]): the service is always called first with
/// no Apple code at all, regardless of platform or linked providers - the
/// server's own Step 3 fails closed with `apple_code_required` before any
/// destructive step if one is actually still needed (nothing yet touched),
/// and a retry after a prior successful revoke needs none at all (#527/
/// #605's identity-bound deletion-progress marker, a "code-free retry").
/// Only then, and only when this platform actually has the native Sign in
/// with Apple ceremony available (`_canAddApple` - an account can carry an
/// Apple identity linked from a different, iOS device while this one has
/// none), does a *second* system-UI window fetch a fresh Apple
/// authorization code (KTD3) and retry once more - a cancelled Apple sheet
/// cancels silently either way. Then the one device reset (`_reset`,
/// KTD16). No reset runs on any failure (R12); each [AccountDeletionFailure]
/// renders its own copy in `account-delete-error`.
///
/// Route naming (U2 Approach 2b): this file's four `showDialog` calls
/// (remove-method confirm, the two sign-out confirms, sign-out-everywhere
/// confirm) are deliberately left unnamed — each is a trivial confirm/
/// cancel choice with no content beyond the consequence copy, not a
/// distinct destination.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show
        GateController,
        RemoveAllPushRegistrationsCallback;
import 'package:lunarlog/ui/account/device_reset_callback.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/export/account_export_writer.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/care_note.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/guardian_note.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/visit_prep_item.dart';
import 'package:lunarlog/domain/repositories/account_export_snapshot_repository.dart';
import 'package:lunarlog/domain/repositories/care_content_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart'
    show ProfileLifecycleMode;
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/delete_account_dialog.dart';
import 'package:lunarlog/ui/account/export_account_collaborator.dart';
import 'package:lunarlog/ui/account/mfa_settings_section.dart';
import 'package:lunarlog/ui/account/mfa_step_up_dialog.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/components/inline_error.dart';
import 'package:lunarlog/ui/l10n/auth_failure_copy.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Generic, provider-free copy per [AccountDeletionFailure] kind (Issue #17
/// U6; R10), the same shape as [authFailureCopy]. [AccountDeletionFailure
/// .appleRevokeFailed] gets a distinct line: the server rows are already
/// gone, but the account itself was deliberately left intact and the whole
/// call is safe to retry (#17 KTD4). [AccountDeletionFailure
/// .appleCodeRequired] gets its own distinct line too (#17 P1 round 2 fix):
/// unlike [AccountDeletionFailure.appleRevokeFailed], nothing was touched
/// on this path at all, so its copy must not claim any data was deleted.
/// [AccountDeletionFailure.appleNativeCeremonyUnavailable] (Issue #605/
/// LLA-052, client-side only - see [_deleteAccountServerInformed]) gets its
/// own line too: unlike [AccountDeletionFailure.appleCodeRequired], a bare
/// retry can never succeed here, since this platform will never grow a
/// native Apple ceremony on its own - the copy points to another device or
/// support instead.
/// [AccountDeletionFailure.appleRevocationMarkerFailed] (Issue #599) gets
/// its own line too, distinct from [AccountDeletionFailure.appleRevokeFailed]:
/// Apple DID confirm the revocation here, so that failure's "Apple could
/// not confirm" claim would be false - only the server's own durable
/// record of the revocation failed to write.
/// [AccountDeletionFailure.attachmentCleanupFailed] (Issue #243 round 2
/// fix, 2026-09-08) gets the same "nothing was touched" treatment as
/// [AccountDeletionFailure.appleCodeRequired]: the attachment-cleanup step
/// now runs before the destructive RPC, so a failure there leaves every
/// row, the Apple grant, and `auth.users` untouched.
/// [AccountDeletionFailure.attachmentCleanupUnbounded] (Issue #559; Issue
/// #605/LLA-053) gets its own copy too, distinct from
/// [AccountDeletionFailure.attachmentCleanupFailed]: it is a bound on the
/// account's own data, not a transient failure, so its copy must not invite
/// a bare retry - only support can resolve it.
///
/// Split into this dispatcher plus [_nothingWasDeletedCopy]/
/// [_dataAlreadyDeletedCopy]/[_otherFailureCopy] (review fix: quality
/// gate's per-method CRAP threshold) - same copy strings, same kinds, no
/// behavior change. The dispatcher's own `switch` stays exhaustive over
/// every [AccountDeletionFailure] subtype (a new variant with no arm here
/// is a compile error), grouped by what each kind's copy actually needs to
/// say: nothing was touched, the account's data is already gone, or
/// everything else. Each helper's own `switch` is narrowed to only the
/// subtypes its dispatcher arm actually sends it, so its `_ =>` default
/// (unreachable in practice) does not weaken the dispatcher's own
/// exhaustiveness check.
String accountDeletionFailureCopy(AccountDeletionFailure failure) =>
    switch (failure) {
      AccountDeletionNetworkFailure() ||
      AccountDeletionAppleCodeRequiredFailure() ||
      AccountDeletionAppleNativeCeremonyUnavailableFailure() ||
      AccountDeletionAttachmentCleanupFailedFailure() ||
      AccountDeletionAttachmentCleanupUnboundedFailure() ||
      AccountDeletionMfaRequiredFailure() =>
        _nothingWasDeletedCopy(failure),
      AccountDeletionAppleRevokeFailedFailure() ||
      AccountDeletionAppleRevocationMarkerFailedFailure() ||
      AccountDeletionDeleteUserFailedFailure() =>
        _dataAlreadyDeletedCopy(failure),
      AccountDeletionUnauthorizedFailure() ||
      AccountDeletionTimeoutFailure() ||
      AccountDeletionUnknownFailure() =>
        _otherFailureCopy(failure),
    };

/// The account-deletion call failed closed before touching anything -
/// nothing was deleted, the account, its rows, and this device's data are
/// all still intact. [AccountDeletionFailure.appleNativeCeremonyUnavailable]
/// and [AccountDeletionFailure.attachmentCleanupUnbounded] still belong
/// here even though a bare retry can never clear either one: "nothing was
/// touched" is equally true for them, only the next-step guidance differs.
String _nothingWasDeletedCopy(AccountDeletionFailure failure) =>
    switch (failure) {
      AccountDeletionNetworkFailure() =>
        'Could not reach the server. Check your connection and try again. '
            'Your account was not deleted.',
      AccountDeletionAppleCodeRequiredFailure() =>
        'Nothing was deleted. We couldn\'t confirm your Apple sign-in '
            'before starting, so the deletion never began - please try '
            'again.',
      AccountDeletionAppleNativeCeremonyUnavailableFailure() =>
        'Nothing was deleted. This account\'s Apple sign-in link can only '
            'be removed from a device that supports Sign in with Apple '
            '(iPhone or iPad) - please finish deleting your account there, '
            'or contact support to remove the Apple link for you.',
      AccountDeletionAttachmentCleanupFailedFailure() =>
        'Nothing was deleted. We couldn\'t remove your support attachments, '
            'so the deletion never began - please try again.',
      AccountDeletionAttachmentCleanupUnboundedFailure() =>
        'Nothing was deleted. Your account has more support attachments '
            'than we can clean up automatically, so the deletion never '
            'began. Retrying won\'t help - please contact support so we can '
            'finish removing your account.',
      AccountDeletionMfaRequiredFailure() =>
        'Nothing was deleted. Please confirm your two-factor code and try '
            'again.',
      _ => throw StateError(
          'unreachable: $failure is not a "nothing was deleted" kind'),
    };

/// The account-deletion call already removed the caller's server-side data
/// (and, for [AccountDeletionFailure.appleRevocationMarkerFailed], Apple
/// already confirmed the sign-in revocation too) - only one last step
/// failed, so the copy must never claim "your account was not deleted".
String _dataAlreadyDeletedCopy(AccountDeletionFailure failure) =>
    switch (failure) {
      AccountDeletionAppleRevokeFailedFailure() =>
        'Your account data was deleted, but Apple could not confirm the '
            'sign-in revocation, so your account sign-in itself still '
            'exists. Try again to finish removing it, or contact support if '
            'you\'re concerned about the lingering Apple access.',
      AccountDeletionAppleRevocationMarkerFailedFailure() =>
        'Your account data was deleted, and Apple confirmed the sign-in '
            'revocation, but we couldn\'t safely record that on our end. '
            'Please try again in a moment, or contact support if it keeps '
            'failing.',
      AccountDeletionDeleteUserFailedFailure() =>
        'Your account data has already been deleted, but removing the '
            'account sign-in itself did not finish. Please try again in a '
            'moment, or contact support if it keeps failing.',
      _ => throw StateError(
          'unreachable: $failure is not a "data already deleted" kind'),
    };

/// Everything else: an expired session, a call whose outcome is genuinely
/// unknown (KTD4), or an unclassified error.
String _otherFailureCopy(AccountDeletionFailure failure) => switch (failure) {
      AccountDeletionUnauthorizedFailure() =>
        'Your session has expired. Sign in again and retry - your account '
            'was not deleted.',
      AccountDeletionTimeoutFailure() =>
        'This is taking longer than expected and we can\'t confirm whether '
            'your account was deleted. Wait a moment and check whether '
            'you\'re still signed in before retrying - retrying is safe '
            'either way.',
      AccountDeletionUnknownFailure() =>
        'Something went wrong. Your account was not deleted. Please try '
            'again.',
      _ => throw StateError('unreachable: $failure is not an "other" kind'),
    };

/// Injectable seam for the Apple authorization-code fetch (Issue #17 U6;
/// KTD3): the default calls the real native dialog with no scopes (only
/// the `authorizationCode` is needed for revocation - not an email or full
/// name); tests substitute a fake and never touch the platform channel.
typedef AppleAuthorizationCodeRequest = Future<AuthorizationCredentialAppleID>
    Function();

Future<AuthorizationCredentialAppleID> _defaultAppleAuthorizationCodeRequest() =>
    SignInWithApple.getAppleIDCredential(scopes: const []);

/// The result of [_AccountSectionState._deleteAccountServerInformed]/
/// [_AccountSectionState._retryWithFreshAppleCode] (Issue #605/LLA-052):
/// [cancelled] means an Apple sheet was dismissed mid-flow, which
/// [_AccountSectionState._performDeletion] treats as a silent abort (no
/// error copy, no device reset) - distinct from [completed], after which
/// the caller proceeds to the device reset.
enum _AppleFlowOutcome { completed, cancelled }

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
    this.showAddPasskey,
    this.showExportAndDelete,
    this.exportAccount,
    this.appleAuthorizationCodeRequest,
  });

  /// Whether "Add Google" may render; null means [AppConfig.hasGoogle]
  /// (#2 U5). Injectable so tests exercise the action without defines.
  final bool? showAddGoogle;

  /// Whether "Add Apple" may render; null means "iOS, not web" (#2 U5).
  final bool? showAddApple;

  /// Whether "Add a passkey" may render; null means [AppConfig.hasPasskeys]
  /// (#30 U4; KTD5). Injectable so widget tests can force the flag on even
  /// though [AppConfig] is compile-time const.
  final bool? showAddPasskey;

  /// Whether "Delete account" may render at all; null means "not web"
  /// (Issue #17 R11 - it never ships on web, regardless of
  /// `LUNARLOG_WEB_SYNC`). Named for the tile it used to gate alongside
  /// "Export my data" before that tile moved out (Issue #222) - kept as-is
  /// rather than renamed, since existing callers already pass it by name.
  /// Injectable so tests simulate web without actually running on it.
  final bool? showExportAndDelete;

  /// Export collaborator for the delete-confirmation dialog's "Export
  /// first" step (Issue #17 U5/U6); null means
  /// [defaultExportAccountCollaborator] (the real platform writer).
  /// Injectable so tests never touch `path_provider`/`share_plus`. Not
  /// related to `YourDataSection`'s own, independently injectable
  /// collaborator (Issue #222) - the two sections share the typedef, not an
  /// instance.
  final ExportAccountCollaborator? exportAccount;

  /// Apple authorization-code fetch (Issue #17 U6; KTD3); null means
  /// [_defaultAppleAuthorizationCodeRequest]. Injectable so tests never
  /// touch the platform channel.
  final AppleAuthorizationCodeRequest? appleAuthorizationCodeRequest;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  /// Not a real [AuthProviders] value — passkeys are not identity providers
  /// and never appear in [AuthUser.providers] (#30 R10) — just the key
  /// [_busyProvider] uses to track a mid-ceremony "Add a passkey" tap,
  /// alongside the real `google`/`apple` provider ids.
  static const _kPasskeyBusyKey = 'passkey';

  /// The provider whose link or remove call is in flight, or null (#31
  /// KTD8). One action at a time, in either direction: every method tile
  /// is disabled while this is set, and a second tap does nothing.
  String? _busyProvider;
  String? _linkError;

  /// Delete's busy flag (Issue #17 U6; narrowed from a shared export/delete
  /// enum by Issue #222, since export no longer has a tile in this section
  /// to race against).
  bool _deleting = false;
  String? _deleteError;

  bool get _canAddGoogle => widget.showAddGoogle ?? AppConfig.hasGoogle;

  bool get _canAddApple =>
      widget.showAddApple ??
      computeAppleSignInAvailable(
        isWeb: kIsWeb,
        isIos: defaultTargetPlatform == TargetPlatform.iOS,
      );

  bool get _canAddPasskey => widget.showAddPasskey ?? AppConfig.hasPasskeys;

  bool get _canExportAndDelete => widget.showExportAndDelete ?? !kIsWeb;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthController?>(context);
    if (auth == null) return const SizedBox.shrink();
    final sync = Provider.of<SyncStatusController?>(context);
    final deletionService = Provider.of<AccountDeletionService?>(context);
    final signedIn = auth.state.hasUsableSession;
    // Issue #32 AC1: linking runs [_requireSignedInUser], which accepts
    // `signedIn` only — under `passwordRecovery` the tile would render and
    // then fail after the credential prompt. The add/remove-method tiles
    // render only for a strictly signed-in session.
    final canLink = auth.state == AuthSessionState.signedIn;
    final theme = Theme.of(context);
    final user = auth.currentUser;
    final providers = user?.providers ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            AppLocalizations.of(context).accountSectionTitle,
            style: theme.textTheme.titleSmall,
          ),
        ),
        if (signedIn)
          ..._buildSignedInIdentityTiles(auth, user, providers, canLink)
        else
          _buildSignInTile(context, auth),
        const SyncStatusTile(),
        if (signedIn && sync != null) _buildSyncNowTile(sync),
        if (signedIn) ..._buildSignOutTiles(context),
        // Issue #268: optional TOTP enrolment/removal, self-contained.
        // Issue #738: the section self-hides when the build's MFA flag is
        // off (AuthController.mfaEnabled), so no tile group renders and no
        // factor call is made in the default build.
        if (signedIn) MfaSettingsSection(auth: auth),
        if (signedIn && _canExportAndDelete)
          ..._buildDeleteTile(context, theme, deletionService),
      ],
    );
  }

  /// The identity tile, any link-failure copy, the "Remove Apple"/"Remove
  /// Google" tiles (#31 U4), and the "Add Apple"/"Add Google" tiles for a
  /// signed-in operator. The method tiles additionally require [canLink] —
  /// a strict `signedIn` session (issue #32 AC1): the link/unlink calls
  /// reject any other state, so under `passwordRecovery` the tiles stay
  /// hidden instead of failing after the credential prompt. Split into
  /// this dispatcher plus [_buildRemoveMethodTiles]/[_buildAddMethodTiles]
  /// — same tiles, same conditions, no behavior change — so no one method
  /// trips the CRAP gate's per-method complexity threshold.
  List<Widget> _buildSignedInIdentityTiles(
    AuthController auth,
    AuthUser? user,
    List<String> providers,
    bool canLink,
  ) {
    final l10n = AppLocalizations.of(context);
    final linkError = _linkError;
    return [
      ListTile(
        key: const ValueKey('account-identity'),
        leading: const Icon(Icons.person_outline),
        title: Text(
            user?.email == null
                ? l10n.accountSectionSignedIn
                : l10n.accountSectionSignedInAs(user!.email!)),
        subtitle: providers.isEmpty
            ? null
            : Text(l10n.accountSectionSignInMethods(
                providers.map(providerLabel).join(', '))),
      ),
      if (linkError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InlineError(
            key: const ValueKey('account-link-error'),
            message: linkError,
          ),
        ),
      if (canLink) ..._buildRemoveMethodTiles(providers),
      if (canLink) ..._buildAddMethodTiles(auth, providers),
    ];
  }

  /// The "Remove Apple"/"Remove Google" tiles (#31 U4).
  List<Widget> _buildRemoveMethodTiles(List<String> providers) => [
        if (_isRemovable(AuthProviders.apple, providers))
          _removeMethodTile(
            provider: AuthProviders.apple,
            onTap: () => _removeMethod(AuthProviders.apple),
          ),
        if (_isRemovable(AuthProviders.google, providers))
          _removeMethodTile(
            provider: AuthProviders.google,
            onTap: () => _removeMethod(AuthProviders.google),
          ),
      ];

  /// The "Add Apple"/"Add Google"/"Add a passkey" tiles for a strictly
  /// signed-in operator (issue #32 AC1).
  List<Widget> _buildAddMethodTiles(
      AuthController auth, List<String> providers) => [
        if (_canAddApple && !providers.contains(AuthProviders.apple))
          _addMethodTile(
            key: 'account-add-apple',
            provider: AuthProviders.apple,
            icon: Icons.apple,
            label: AppLocalizations.of(context).accountSectionAddApple,
            onTap: () => _addMethod(AuthProviders.apple, auth.linkApple),
          ),
        if (_canAddGoogle && !providers.contains(AuthProviders.google))
          _addMethodTile(
            key: 'account-add-google',
            provider: AuthProviders.google,
            icon: Icons.add_link,
            label: AppLocalizations.of(context).accountSectionAddGoogle,
            onTap: () => _addMethod(AuthProviders.google, auth.linkGoogle),
          ),
        if (_canAddPasskey)
          _addMethodTile(
            key: 'account-add-passkey',
            provider: _kPasskeyBusyKey,
            icon: Icons.fingerprint,
            label: AppLocalizations.of(context).accountSectionAddPasskey,
            onTap: () =>
                _addMethod(_kPasskeyBusyKey, () => _registerPasskey(auth)),
          ),
      ];

  /// Adapts [AuthController.registerPasskey]'s
  /// [NativeSignInResult] to the `Future<AuthUser>` shape
  /// [_addMethod]/[_reauthenticateAndLink] share with [linkGoogle] and
  /// [linkApple] (#30 U4; KTD5). A dismissed ceremony has no fresh user to
  /// report — the controller adopted nothing — so the current user is
  /// returned unchanged, exactly as a dismissed Google/Apple picker leaves
  /// it (`_link` in `SupabaseAuthService`).
  Future<AuthUser> _registerPasskey(AuthController auth) async {
    final result = await auth.registerPasskey();
    return switch (result) {
      NativeSignInSession(:final user) => user,
      NativeSignInCancelled() => auth.currentUser!,
    };
  }

  Widget _buildSignInTile(BuildContext context, AuthController auth) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('account-sign-in'),
      leading: const Icon(Icons.login),
      title: Text(
          auth.state == AuthSessionState.expired
              ? l10n.accountSectionSignInAgain
              : l10n.accountSectionSignIn),
      subtitle: Text(l10n.accountSectionSyncSubtitle),
      onTap: () => pushNamedScreen<void>(context, kRouteSignInScreen),
    );
  }

  Widget _buildSyncNowTile(SyncStatusController sync) {
    return ListTile(
      key: const ValueKey('account-sync-now'),
      leading: const Icon(Icons.sync),
      title: Text(AppLocalizations.of(context).accountSectionSyncNow),
      enabled: !isSyncRunning(sync.snapshot),
      onTap: sync.requestSync,
    );
  }

  List<Widget> _buildSignOutTiles(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      ListTile(
        key: const ValueKey('account-sign-out'),
        leading: const Icon(Icons.logout),
        title: Text(l10n.accountSectionSignOut),
        subtitle: Text(l10n.accountSectionSignOutSubtitle),
        onTap: () => _signOut(context),
      ),
      ListTile(
        key: const ValueKey('account-sign-out-everywhere'),
        leading: const Icon(Icons.devices_other),
        title: Text(l10n.accountSectionSignOutEverywhere),
        subtitle: Text(l10n.accountSectionSignOutEverywhereSubtitle),
        onTap: () => _signOutEverywhere(context),
      ),
    ];
  }

  /// The delete tile and its inline error copy (Issue #17 U6). "Export my
  /// data" used to sit alongside this before Issue #222 moved it to
  /// `YourDataSection`.
  List<Widget> _buildDeleteTile(
    BuildContext context,
    ThemeData theme,
    AccountDeletionService? deletionService,
  ) {
    return [
      if (deletionService != null)
        ListTile(
          key: const ValueKey('account-delete'),
          leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
          title: Text(AppLocalizations.of(context).accountSectionDelete,
              style: TextStyle(color: theme.colorScheme.error)),
          subtitle: Text(
              AppLocalizations.of(context).accountDeleteTileSubtitle),
          enabled: !_deleting,
          trailing: _deleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: !_deleting ? () => _deleteAccount(context) : null,
        ),
      if (_deleteError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InlineError(
            key: const ValueKey('account-delete-error'),
            message: _deleteError!,
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
    final busy = _busyProvider == provider;
    return ListTile(
      key: ValueKey(key),
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(AppLocalizations.of(context).accountSectionLinkSubtitle),
      enabled: _busyProvider == null,
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _busyProvider == null ? onTap : null,
    );
  }

  /// A method is removable when it is not `email` and the account holds
  /// at least one other method (#31 R2).
  bool _isRemovable(String provider, List<String> providers) =>
      provider != AuthProviders.email &&
      providers.contains(provider) &&
      providers.length >= 2;

  ListTile _removeMethodTile({
    required String provider,
    required VoidCallback onTap,
  }) {
    final busy = _busyProvider == provider;
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: ValueKey('account-remove-$provider'),
      leading: Icon(provider == AuthProviders.apple ? Icons.apple : Icons.link_off),
      title: Text(l10n.accountSectionRemoveProvider(providerLabel(provider))),
      subtitle: Text(l10n.accountSectionRemoveSubtitle),
      enabled: _busyProvider == null,
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _busyProvider == null ? onTap : null,
    );
  }

  /// F5: device credential first (KTD5), then the provider picker through
  /// the controller. A declined credential calls no provider and renders one
  /// "Couldn't confirm it's you" line (issue #984) rather than ending the
  /// action silently.
  ///
  /// Both ceremonies run inside one system-UI window (#65 U2; KTD6) — the
  /// credential prompt nests its own inside it, which the window's depth
  /// counter handles — so neither the prompt nor the picker re-locks the
  /// app on the way through.
  Future<void> _addMethod(
      String provider, Future<AuthUser> Function() link) async {
    if (_busyProvider != null) return;
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
    if (!await _reauthenticate(gate)) return;
    if (!mounted) return;
    setState(() => _busyProvider = provider);
    try {
      // The controller adopts the returned user into `currentUser` itself
      // and notifies (#31 finding 2); this widget listens via
      // `Provider.of` in [build], so no local state update is needed here.
      await link();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() => _linkError =
            authFailureCopy(AppLocalizations.of(context), failure));
      }
    } catch (error) {
      debugPrint('lunarlog account: link failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _linkError = authFailureCopy(
            AppLocalizations.of(context), const AuthFailure.unknown()));
      }
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  /// Issue #984: a failed re-auth used to end the action silently, which on a
  /// Face ID loop was indistinguishable from a hang. Surface one line instead.
  /// The copy is resolved before the await (the action may unmount this
  /// widget, and `context` must not be touched across the gap).
  Future<bool> _reauthenticate(GateController gate) async {
    final copy = AppLocalizations.of(context).accountReauthFailed;
    final granted = await gate.reauthenticate();
    if (!granted && mounted) setState(() => _linkError = copy);
    return granted;
  }

  /// F1/F2/F3: confirmation dialog first (#31 KTD7) — before the
  /// system-UI window, since it is Flutter UI, not system UI — then the
  /// same device-credential-plus-provider-call ceremony as adding (KTD8).
  /// Cancelling the confirmation ends the action with no credential prompt,
  /// no service call, and no copy (R4); a failed *credential* renders the
  /// issue #984 line instead of returning silently.
  Future<void> _removeMethod(String provider) async {
    if (_busyProvider != null) return;
    final gate = context.read<GateController?>();
    if (gate == null) {
      debugPrint('lunarlog account: no gate to re-authenticate with');
      return;
    }
    final auth = context.read<AuthController>();
    setState(() => _linkError = null);
    final l10n = AppLocalizations.of(context);
    final label = providerLabel(provider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.accountSectionRemoveTitle(label)),
        content: Text(l10n.accountSectionRemoveBody(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.accountSectionCancel),
          ),
          FilledButton(
            key: const ValueKey('account-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.accountSectionRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await gate.duringSystemUi(
        () => _reauthenticateAndRemove(gate, auth, provider));
  }

  Future<void> _reauthenticateAndRemove(
      GateController gate, AuthController auth, String provider) async {
    if (!await _reauthenticate(gate)) return;
    if (!mounted) return;
    setState(() => _busyProvider = provider);
    try {
      // Same as adding: the controller adopts and notifies itself (#31
      // finding 2), so no local state update is needed here.
      await auth.unlinkProvider(provider);
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() => _linkError =
            authFailureCopy(AppLocalizations.of(context), failure));
      }
    } catch (error) {
      debugPrint('lunarlog account: unlink failed (${error.runtimeType})');
      if (mounted) {
        setState(() => _linkError = authFailureCopy(
            AppLocalizations.of(context), const AuthFailure.unknown()));
      }
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  /// Runs the reset from the app's root route: the Settings route is
  /// popped first because the reset unmounts the whole tree beneath the
  /// root, and a pushed route would otherwise outlive its providers in
  /// harnesses that stub the reset.
  ///
  /// [reset] may be passed in already resolved (Issue #17 P1 fix, also
  /// applied to the global sign-out path by Issue #638/LLA-004) for a
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
    final l10n = AppLocalizations.of(context);
    final sync = context.read<SyncStatusController?>();
    final dirty = sync?.snapshot.dirtyCount ?? 0;
    final bool? discard;
    if (dirty > 0) {
      discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.accountSectionUnsyncedTitle),
          content: Text(l10n.accountSectionUnsyncedBody(dirty)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(l10n.accountSectionCancel),
            ),
            TextButton(
              key: const ValueKey('account-sign-out-sync'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.accountSectionSyncNow),
            ),
            FilledButton(
              key: const ValueKey('account-sign-out-discard'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.accountSectionDiscardAndSignOut),
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
          title: Text(l10n.accountSectionSignOutTitle),
          content: Text(l10n.accountSectionSignOutBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(l10n.accountSectionCancel),
            ),
            FilledButton(
              key: const ValueKey('account-sign-out-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.accountSectionSignOut),
            ),
          ],
        ),
      );
    }
    if (discard != true || !context.mounted) return;
    await _reset(context);
  }

  Future<void> _signOutEverywhere(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.accountSectionSignOutEverywhereTitle),
        content: Text(l10n.accountSignOutEverywhereBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.accountSectionCancel),
          ),
          FilledButton(
            key: const ValueKey('account-sign-out-everywhere-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.accountSectionSignOutEverywhere),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final auth = context.read<AuthController>();
    // #268 D-6: AAL2 step-up before ending every session, for an account
    // with an enrolled TOTP factor; a no-op otherwise.
    if (!await ensureAal2(context, auth) || !context.mounted) return;
    final removeAllRegistrations =
        context.read<RemoveAllPushRegistrationsCallback?>();
    // Issue #638 (LLA-004): resolved here, before the awaits below, the
    // same way _performDeletion resolves it for Issue #17 (see _reset's doc
    // comment). Settings - and this widget - can unmount mid-flight because
    // signing out navigates away, so the reset must not depend on [context]
    // still being valid once signOut() and the push deregistration below
    // have completed; only the UI feedback (the snackbar, _reset's own pop)
    // stays gated on context.mounted.
    final resetCallback = context.read<DeviceResetCallback?>();
    // #1/#9 (review fix): remove *every* device's push registration while
    // the session is still authenticated, before signOut() clears it - see
    // RemoveAllPushRegistrationsCallback's doc comment. This is the global
    // ("everywhere") path: signOut(scope: global) below revokes every
    // device's session server-side, so its push registration must go too,
    // not just this device's (which RemovePushRegistrationCallback alone
    // would leave behind on every other device). _reset(context) below
    // (resetDevice) also attempts a single-device removal, but by then
    // signOut() has already cleared the session, so that attempt alone runs
    // as anon and is denied.
    await removeAllRegistrations?.call();
    try {
      await auth.signOut(scope: AuthSignOutScope.global);
    } on AuthFailure catch (failure) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.accountSectionOtherDevicesNotSignedOut(
              authFailureCopy(l10n, failure))),
        ));
      }
      // Always run, whether or not context is still mounted (Issue #638) -
      // see _reset's doc comment: [resetCallback] was captured above, so the
      // data wipe still happens even though the route that started this
      // flow is gone; only _reset's own UI pop is gated internally.
      // ignore: use_build_context_synchronously
      await _reset(context, reset: resetCallback);
      return;
    }
    // Same reasoning as the catch block above: always run regardless of
    // context.mounted (Issue #638).
    // ignore: use_build_context_synchronously
    await _reset(context, reset: resetCallback);
  }

  /// Collects this device's profiles and their entries and hands them to
  /// the export collaborator (Issue #17 U5/U6; KTD5). Does not catch: its
  /// one remaining caller, the delete dialog's "Export first" (Issue #222
  /// moved the standalone tile to `YourDataSection`, which calls the same
  /// collaborator independently rather than through this method), renders
  /// the failure its own way.
  Future<void> _runExport(BuildContext context) async {
    final profilesRepo = context.read<ProfilesRepository>();
    // Issue #140 review, LLA-094: entries/observations (plus, LLA-084,
    // profileMode/cycleOverrides) are read together per profile through
    // this one coherent snapshot seam — see
    // `AccountExportSnapshotRepository`'s own doc comment.
    final snapshotRepo = context.read<AccountExportSnapshotRepository>();
    final careContentRepo = context.read<CareContentRepository>();
    // Issue #248: read before the first `await` below (not after -
    // `use_build_context_synchronously`). The writer already carries its
    // optional server-side remote source from construction; an
    // unconfigured build (no Supabase client) resolves to a local-only
    // document - the same "nothing to merge" degrade as a configured
    // remote source that itself resolves to null (signed out, offline, a
    // server error).
    final exportWriter = context.read<AccountExportWriter>();
    final profiles = await profilesRepo.list();
    final entriesByProfile = <String, List<DayEntry>>{};
    final observationsByProfile = <String, List<Observation>>{};
    final careNotesByProfile = <String, List<CareNote>>{};
    final visitPrepByProfile = <String, List<VisitPrepItem>>{};
    final profileModesByProfile = <String, ProfileLifecycleMode?>{};
    final cycleOverridesByProfile = <String, List<CycleOverride>>{};
    final mergeEventsByProfile = <String, List<DayEntryMergeEvent>>{};
    final customTagsByProfile = <String, List<CustomTag>>{};
    final guardianNotesByProfile = <String, List<GuardianNote>>{};
    for (final profile in profiles) {
      final snapshot = await snapshotRepo.forProfile(profile.id);
      entriesByProfile[profile.id] = snapshot.entries;
      observationsByProfile[profile.id] = snapshot.observations;
      profileModesByProfile[profile.id] = snapshot.profileMode;
      cycleOverridesByProfile[profile.id] = snapshot.cycleOverrides;
      mergeEventsByProfile[profile.id] = snapshot.mergeEvents;
      customTagsByProfile[profile.id] = snapshot.customTags;
      guardianNotesByProfile[profile.id] = snapshot.guardianNotes;
      careNotesByProfile[profile.id] =
          await careContentRepo.listCareNotes(profile.id);
      visitPrepByProfile[profile.id] =
          await careContentRepo.listPrepItems(profile.id);
    }
    await (widget.exportAccount ??
        defaultExportAccountCollaborator(exportWriter))(
      profiles: profiles,
      entriesByProfile: entriesByProfile,
      observationsByProfile: observationsByProfile,
      careNotesByProfile: careNotesByProfile,
      visitPrepByProfile: visitPrepByProfile,
      profileModesByProfile: profileModesByProfile,
      cycleOverridesByProfile: cycleOverridesByProfile,
      mergeEventsByProfile: mergeEventsByProfile,
      customTagsByProfile: customTagsByProfile,
      guardianNotesByProfile: guardianNotesByProfile,
      appVersion: kAppVersionForExport,
    );
  }

  /// Delete flow (Issue #17 U6; R1-R3, R6, R12, KTD7). In order: a fresh
  /// device credential (declining cancels silently, AE5); the confirmation
  /// naming server rows, the account, and this device's data, with
  /// "Export first" available without proceeding (R2); the server-informed
  /// Apple flow (Issue #605/LLA-052; see [_deleteAccountServerInformed]);
  /// then the one device reset (KTD16). No reset runs on any failure (R12).
  Future<void> _deleteAccount(BuildContext context) async {
    if (_deleting) return;
    final gate = context.read<GateController?>();
    if (gate == null) {
      debugPrint('lunarlog account: no gate to re-authenticate with');
      return;
    }
    setState(() => _deleteError = null);
    if (!await _passesPreDeleteChecks(context, gate) || !context.mounted) {
      return;
    }

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

    await _performDeletion(context, gate, service);
  }

  /// The device credential and, when the account has an enrolled TOTP
  /// factor, an AAL2 step-up (#268 D-6) — both must pass before the delete
  /// confirmation dialog even opens. Split out of [_deleteAccount] to keep
  /// that method's own cyclomatic complexity under the CRAP gate's budget.
  Future<bool> _passesPreDeleteChecks(
    BuildContext context,
    GateController gate,
  ) async {
    final granted = await gate.duringSystemUi(gate.reauthenticate);
    if (!granted || !context.mounted) return false;
    final auth = context.read<AuthController>();
    return await ensureAal2(context, auth) && context.mounted;
  }

  /// The service call itself, once the credential and confirmation steps
  /// have passed - [_deleteAccountServerInformed]'s server-informed Apple
  /// flow, then the one device reset (R6, KTD16). No reset runs on any
  /// failure (R12), including a cancelled Apple ceremony mid-flow (KTD3).
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
  ) async {
    final resetCallback = context.read<DeviceResetCallback?>();
    setState(() => _deleting = true);
    try {
      final outcome = await _deleteAccountServerInformed(gate, service);
      if (outcome == _AppleFlowOutcome.cancelled) return;
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
      if (mounted) setState(() => _deleting = false);
    }
    // context is intentionally used here whether or not it is still mounted
    // (Issue #17 P1 fix): _reset only ever uses it for the UI pop, gated on
    // context.mounted internally, and always calls resetCallback (the data
    // wipe) regardless.
    // ignore: use_build_context_synchronously
    await _reset(context, reset: resetCallback);
  }

  /// The server-informed Apple flow the finding's own "Response and
  /// targeted regression" describes (Issue #605/LLA-052). Always calls the
  /// service first with NO Apple code, regardless of platform or whether
  /// the account carries an Apple identity at all - the server's own Step 3
  /// (`delete-account/index.ts`) fails closed with `apple_code_required`
  /// *before* any destructive step whenever one is actually still needed,
  /// so nothing is touched by this first attempt either way; and #527/#605's
  /// identity-bound deletion-progress marker means a retry after a prior
  /// successful revoke needs no code at all (a "code-free retry" - the
  /// ceremony is never invoked). Only when the server actually asks for a
  /// code does [_retryWithFreshAppleCode] run.
  Future<_AppleFlowOutcome> _deleteAccountServerInformed(
    GateController gate,
    AccountDeletionService service,
  ) async {
    try {
      await service.deleteAccount();
      return _AppleFlowOutcome.completed;
    } on AccountDeletionAppleCodeRequiredFailure {
      return _retryWithFreshAppleCode(gate, service);
    }
  }

  /// Fetches a fresh Apple authorization code and retries once - reached
  /// only after the server has just said it still needs one. Throws
  /// [AccountDeletionFailure.appleNativeCeremonyUnavailable] instead of ever
  /// invoking the native ceremony on a platform that does not have it
  /// (Issue #605/LLA-052, `_canAddApple`): `SignInWithApple
  /// .getAppleIDCredential` throws `SignInWithAppleNotSupportedException`
  /// there, which used to surface as generic "please try again" copy that
  /// could never actually succeed by retrying - this account's Apple
  /// sign-in link can only be removed from a device that has the ceremony,
  /// or by support.
  Future<_AppleFlowOutcome> _retryWithFreshAppleCode(
    GateController gate,
    AccountDeletionService service,
  ) async {
    if (!_canAddApple) {
      throw const AccountDeletionFailure.appleNativeCeremonyUnavailable();
    }
    final appleCode = await gate.duringSystemUi(_fetchAppleAuthorizationCode);
    if (appleCode == null) return _AppleFlowOutcome.cancelled; // cancelled Apple sheet: silent abort
    await service.deleteAccount(appleAuthorizationCode: appleCode);
    return _AppleFlowOutcome.completed;
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
