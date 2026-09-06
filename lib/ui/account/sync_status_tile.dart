/// Sync status surfaces (U6, Approach 7): one copy function, the Settings
/// tile ([SyncStatusTile]) and the picker's app-bar glyph
/// ([SyncStatusGlyph]). Nothing here carries health content — phases,
/// counts and a relative time only (R18).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lunarlog/config.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/account/upload_consent_screen.dart';
import 'package:provider/provider.dart';

const String kSyncingCopy = 'Syncing…';
const String kUploadPendingCopy = 'Upload pending — tap to review';
const String kWebSyncOffCopy = 'Sync is off in this web build';
const String kSignInAgainCopy = 'Sign in again to sync';
const String kRejectedCopy = 'Some entries could not be uploaded';
const String kAwaitingConfirmationCopy =
    'Waiting for email confirmation — open the link on this device';

/// A passwordless sign-in email is out and no session has arrived yet
/// (#2 U4; KTD3): same tier as the confirmation copy.
const String kAwaitingMagicLinkCopy =
    'Sign-in email sent — open the link on this device or enter the code';

/// "just now", "5 min ago", "3 h ago", "2 d ago".
String formatRelative(DateTime then, DateTime now) {
  final delta = now.toUtc().difference(then.toUtc());
  if (delta < const Duration(minutes: 1)) return 'just now';
  if (delta < const Duration(hours: 1)) return '${delta.inMinutes} min ago';
  if (delta < const Duration(days: 1)) return '${delta.inHours} h ago';
  return '${delta.inDays} d ago';
}

/// The one line the tile and the glyph show. Precedence, most urgent
/// first: the web build's off state; an unconfirmed sign-up; a pending
/// passwordless sign-in email (#2 U4); an auth error; a wrong account;
/// pending upload consent; a running cycle; rejected rows; then the
/// resting states.
bool _isSignedIn(AuthSessionState? authState) =>
    authState == AuthSessionState.signedIn ||
    authState == AuthSessionState.passwordRecovery;

/// Whether the tile should show the "waiting for email confirmation" state:
/// a sign-up is pending on this device and no session has arrived (AS10).
bool isAwaitingConfirmation({
  required AuthSessionState? authState,
  required String? awaitingConfirmationEmail,
}) =>
    !_isSignedIn(authState) &&
    awaitingConfirmationEmail != null &&
    awaitingConfirmationEmail.isNotEmpty;

/// Whether the tile should show the "sign-in email sent" state: a
/// passwordless request is pending on this device and no session has
/// arrived (#2 U4; KTD3). Same rule as [isAwaitingConfirmation].
bool isAwaitingMagicLink({
  required AuthSessionState? authState,
  required String? awaitingMagicLinkEmail,
}) => isAwaitingConfirmation(
  authState: authState,
  awaitingConfirmationEmail: awaitingMagicLinkEmail,
);

String syncStatusCopy({
  required SyncSnapshot? snapshot,
  required AuthSessionState? authState,
  String? awaitingConfirmationEmail,
  String? awaitingMagicLinkEmail,
  required DateTime now,
  bool webSyncOff = false,
}) {
  if (webSyncOff) return kWebSyncOffCopy;
  if (isAwaitingConfirmation(
    authState: authState,
    awaitingConfirmationEmail: awaitingConfirmationEmail,
  )) {
    return kAwaitingConfirmationCopy;
  }
  if (isAwaitingMagicLink(
    authState: authState,
    awaitingMagicLinkEmail: awaitingMagicLinkEmail,
  )) {
    return kAwaitingMagicLinkCopy;
  }
  if (snapshot == null) return 'Sync is not available in this build';
  return _snapshotCopy(
    snapshot: snapshot,
    authState: authState,
    signedIn: _isSignedIn(authState),
    now: now,
  );
}

/// The copy once the web-off / awaiting-confirmation / awaiting-magic-link
/// / no-snapshot tiers (handled by [syncStatusCopy]) are ruled out.
String _snapshotCopy({
  required SyncSnapshot snapshot,
  required AuthSessionState? authState,
  required bool signedIn,
  required DateTime now,
}) {
  if (snapshot.phase == SyncPhase.error) return _errorCopy(snapshot.lastError);
  if (authState == AuthSessionState.expired) return kSignInAgainCopy;
  final phaseCopy = _fixedPhaseCopy(snapshot.phase);
  if (phaseCopy != null) return phaseCopy;
  return _restingStateCopy(snapshot: snapshot, signedIn: signedIn, now: now);
}

/// Copy for a sync-engine failure, keyed by [SyncSnapshot.lastError].
String _errorCopy(SyncErrorKind lastError) => switch (lastError) {
  SyncErrorKind.auth => kSignInAgainCopy,
  SyncErrorKind.network => 'Could not reach the server — will retry',
  SyncErrorKind.other || SyncErrorKind.none => 'Sync failed — will retry',
};

/// Copy fixed by [phase] alone, or `null` to fall through to
/// [_restingStateCopy]'s checks (covers `paused`, `idle` and `error` —
/// `error` is unreachable here, already handled by [_snapshotCopy]).
String? _fixedPhaseCopy(SyncPhase phase) {
  switch (phase) {
    case SyncPhase.accountMismatch:
      return 'Signed in as a different account';
    case SyncPhase.awaitingUploadConsent:
      return kUploadPendingCopy;
    case SyncPhase.restoring:
    case SyncPhase.pushing:
    case SyncPhase.pulling:
      return kSyncingCopy;
    case SyncPhase.paused:
    case SyncPhase.idle:
    case SyncPhase.error:
      return null;
  }
}

/// The resting-state tiers: rejected rows, signed-out, paused, then the
/// last-synced copy.
String _restingStateCopy({
  required SyncSnapshot snapshot,
  required bool signedIn,
  required DateTime now,
}) {
  if (snapshot.rejectedCount > 0) return kRejectedCopy;
  if (!signedIn) return 'Not signed in';
  if (snapshot.phase == SyncPhase.paused) return 'Sync paused';
  final last = snapshot.lastSyncAt;
  if (last == null) return 'Not synced yet';
  return 'Up to date · ${formatRelative(last, now)}';
}

/// Whether the copy describes a running cycle (drives spinners and the
/// "Sync now" enablement).
bool isSyncRunning(SyncSnapshot? snapshot) => switch (snapshot?.phase) {
  SyncPhase.restoring || SyncPhase.pushing || SyncPhase.pulling => true,
  _ => false,
};

IconData _iconFor(
  SyncSnapshot? snapshot, {
  bool webSyncOff = false,
  bool awaitingConfirmation = false,
}) {
  final override = _iconOverride(webSyncOff, awaitingConfirmation, snapshot);
  if (override != null) return override;
  return _iconForPhase(snapshot!.phase, snapshot.rejectedCount);
}

/// The three cases where the phase-based icon never applies: split out of
/// [_iconFor] verbatim — same conditions, no behavior change.
IconData? _iconOverride(
  bool webSyncOff,
  bool awaitingConfirmation,
  SyncSnapshot? snapshot,
) {
  if (webSyncOff) return Icons.cloud_off_outlined;
  if (awaitingConfirmation) return Icons.mark_email_unread_outlined;
  if (snapshot == null) return Icons.cloud_off_outlined;
  return null;
}

IconData _iconForPhase(SyncPhase phase, int rejectedCount) => switch (phase) {
    SyncPhase.error => Icons.cloud_off_outlined,
    SyncPhase.accountMismatch => Icons.no_accounts_outlined,
    SyncPhase.awaitingUploadConsent => Icons.cloud_upload_outlined,
    SyncPhase.restoring ||
    SyncPhase.pushing ||
    SyncPhase.pulling => Icons.cloud_sync_outlined,
    SyncPhase.paused => Icons.pause_circle_outline,
    SyncPhase.idle =>
      rejectedCount > 0
          ? Icons.warning_amber_outlined
          : Icons.cloud_done_outlined,
  };

/// Settings tile (`sync-status`). Reads the nullable controllers from the
/// tree; watches [SettingsKeys.awaitingConfirmationEmail] and
/// [SettingsKeys.awaitingMagicLinkEmail] (#2 U4). Tappable while upload
/// consent is pending: reopens the consent screen (AS4).
class SyncStatusTile extends StatefulWidget {
  const SyncStatusTile({
    super.key,
    this.now,
    this.webSyncOff = kIsWeb && !AppConfig.webSyncEnabled,
  });

  /// Clock for the relative time; injectable for tests.
  final DateTime Function()? now;

  /// AS9: the web build without the define renders the off copy.
  final bool webSyncOff;

  @override
  State<SyncStatusTile> createState() => _SyncStatusTileState();
}

class _SyncStatusTileState extends State<SyncStatusTile> {
  /// The two settings watches are created once per [SettingsStore] instance
  /// rather than on every build: each `watch` opens a live database query,
  /// and the tile rebuilds on every sync-progress notification.
  SettingsStore? _settings;
  Stream<String?>? _awaiting;
  Stream<String?>? _awaitingLink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<SettingsStore?>(context, listen: false);
    if (identical(settings, _settings)) return;
    _settings = settings;
    _awaiting = settings?.watch(SettingsKeys.awaitingConfirmationEmail);
    _awaitingLink = settings?.watch(SettingsKeys.awaitingMagicLinkEmail);
  }

  @override
  Widget build(BuildContext context) {
    final sync = Provider.of<SyncStatusController?>(context);
    final auth = Provider.of<AuthController?>(context);
    final now = widget.now;
    final webSyncOff = widget.webSyncOff;
    return StreamBuilder<String?>(
      stream: _awaiting,
      builder: (context, awaitingSnapshot) => StreamBuilder<String?>(
        stream: _awaitingLink,
        builder: (context, linkSnapshot) {
          final snapshot = sync?.snapshot;
          final copy = syncStatusCopy(
            snapshot: snapshot,
            authState: auth?.state,
            awaitingConfirmationEmail: awaitingSnapshot.data,
            awaitingMagicLinkEmail: linkSnapshot.data,
            now: (now ?? DateTime.now)(),
            webSyncOff: webSyncOff,
          );
          final pendingConsent =
              snapshot?.phase == SyncPhase.awaitingUploadConsent;
          final awaitingEmail =
              isAwaitingConfirmation(
                authState: auth?.state,
                awaitingConfirmationEmail: awaitingSnapshot.data,
              ) ||
              isAwaitingMagicLink(
                authState: auth?.state,
                awaitingMagicLinkEmail: linkSnapshot.data,
              );
          return ListTile(
            key: const ValueKey('sync-status'),
            leading: isSyncRunning(snapshot)
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _iconFor(
                      snapshot,
                      webSyncOff: webSyncOff,
                      awaitingConfirmation: awaitingEmail,
                    ),
                  ),
            title: Text(copy),
            onTap: pendingConsent
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings:
                          const RouteSettings(name: kRouteUploadConsentScreen),
                      builder: (routeContext) => UploadConsentScreen(
                        onNotNow: () => Navigator.of(routeContext).pop(),
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}

/// App-bar glyph for the profile picker: the status as a tooltip, tapping
/// runs [onPressed] (the picker opens Settings). Renders nothing without a
/// [SyncStatusController] — the caller decides, this is a safety net.
class SyncStatusGlyph extends StatelessWidget {
  const SyncStatusGlyph({super.key, required this.onPressed, this.now});

  final VoidCallback onPressed;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final sync = Provider.of<SyncStatusController?>(context);
    if (sync == null) return const SizedBox.shrink();
    final auth = Provider.of<AuthController?>(context);
    final copy = syncStatusCopy(
      snapshot: sync.snapshot,
      authState: auth?.state,
      now: (now ?? DateTime.now)(),
    );
    return IconButton(
      key: const ValueKey('sync-status-glyph'),
      tooltip: copy,
      icon: Icon(_iconFor(sync.snapshot)),
      onPressed: onPressed,
    );
  }
}
