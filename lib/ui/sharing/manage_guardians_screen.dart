/// Screen for viewing, inviting, and revoking caregivers for a profile (U8;
/// R1, R3, R4, R6, R8). Guardian rows come from [ProfileGuardiansRepository]
/// (R14/R16): no Drift row type crosses into this file.
///
/// Route naming: the "Remove guardian?" confirm is a trivial confirm/cancel
/// choice, deliberately left unnamed. [InviteGuardianDialog] is pushed as a
/// modal sheet named [kRouteInviteGuardianSheet] (Issue #250).
///
/// Issue #3 gap-closure plan (Unit U3) adds a pending-invitations section
/// below the guardian list: it lists outstanding invitations and lets an
/// authorized guardian cancel one. It is a `Future`-backed section, not a
/// stream (KTD3) - there is no local table behind pending invitations.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';
import 'package:lunarlog/ui/l10n/sharing_failure_copy.dart';

import '../../domain/repositories/activity_feed_repository.dart';
import '../../domain/repositories/profile_guardians_repository.dart';
import '../../domain/help/help_cards.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/notifications/notification_preferences_service.dart';
import '../../domain/profiles/profile_erasure_service.dart';
import '../../domain/sharing/ownership_transfer_service.dart';
import '../../domain/sharing/prediction_connection_service.dart';
import '../../domain/sharing/sharing_service.dart';
import '../../observability/route_names.dart';
import '../components/destructive_button.dart';
import '../components/inline_error.dart';
import '../help/help_card_view.dart';
import '../routes.dart';
import 'activity_feed_screen.dart';
import 'guardian_watch_mixin.dart';
import 'invite_guardian_dialog.dart';
import 'notification_preferences_screen.dart';
import 'share_predictions_dialog.dart';
import 'transfer_ownership_screen.dart';

class ManageGuardiansScreen extends StatefulWidget {
  const ManageGuardiansScreen({
    super.key,
    required this.profile,
    required this.guardiansRepository,
    required this.sharingService,
    required this.currentUserId,
    this.ownershipTransferService,
    this.notificationPreferencesService,
    this.activityRepository,
    this.predictionConnectionService,
    this.onPredictionConnectionChanged,
    this.profileErasureService,
  });

  final Profile profile;
  final ProfileGuardiansRepository guardiansRepository;
  final SharingService sharingService;

  /// The signed-in user's id, required for role gating (U8): viewers and
  /// caregivers never see the invite action or revocation controls.
  final String? currentUserId;

  /// Null on an unconfigured build (R26) — the transfer-ownership entry
  /// point is hidden whenever this is null, regardless of caller role.
  final OwnershipTransferService? ownershipTransferService;

  /// Issue #5, U8: when present, an AppBar "Notifications" action opens
  /// [NotificationPreferencesScreen]. Null (an unconfigured build, or a
  /// platform/build with push unavailable) hides the action entirely - this
  /// is what keeps R17 true with zero conditionals in the caller.
  final NotificationPreferencesService? notificationPreferencesService;

  /// Issue #124: when present, an AppBar "Activity" action opens
  /// [ActivityFeedScreen] - the feed is reachable from Manage Guardians as
  /// well as from the profile screen. Null (no storage wired at the push
  /// site) hides the action.
  final ActivityFeedRepository? activityRepository;

  /// Issue #151: when present, a "Predictions-only sharing" section sits
  /// below the pending invitations - the primary guardian can arm one
  /// phases-only connection per profile and revoke it, mirroring the
  /// guardian-revocation UX. Null (an unconfigured build) hides the
  /// section entirely, the same null-gating discipline as
  /// [ownershipTransferService].
  final PredictionConnectionService? predictionConnectionService;

  /// Issue #151: called after a prediction connection is created or
  /// revoked so the shell can (re)publish the projection snapshot right
  /// away. Issue #373: also called the moment a pending invite is seen to
  /// have been redeemed (this screen polls the connection while it is
  /// pending) - that is the transition at which a snapshot first becomes
  /// publishable, since the server only accepts one for an ACTIVE
  /// connection; at arming time there is nothing to publish to yet.
  final void Function(String profileId)? onPredictionConnectionChanged;

  /// Issue #472: when present, a "Danger zone" section offers "Delete
  /// profile permanently" to the profile's accepted `primary_guardian`
  /// only — null (an unconfigured build) hides the section entirely, the
  /// same null-gating discipline as [predictionConnectionService].
  final ProfileErasureService? profileErasureService;

  /// Issue #373: how often the screen re-reads a still-pending connection
  /// to catch its redemption. Injectable so tests drive it in fake time.
  static const Duration pendingPollInterval = Duration(seconds: 15);

  @override
  State<ManageGuardiansScreen> createState() => _ManageGuardiansScreenState();
}

class _ManageGuardiansScreenState extends State<ManageGuardiansScreen> {
  /// The pending-invitations section's data (U3; R1, R6). Loaded once on
  /// init, and reloaded after a create or cancel - there is no stream
  /// behind it (KTD3).
  late Future<List<PendingInvite>> _pendingInvitesFuture;

  /// Issue #151: the profile's live prediction connection (pending invite
  /// or active share), or null. Loaded once on init and reloaded after a
  /// create or revoke - read on demand, never synced (KTD3). Null once
  /// loaded means "no connection"; before that, the section shows a
  /// spinner rather than a create affordance built on absent data.
  PredictionConnectionService? get _predictionService =>
      widget.predictionConnectionService;
  ActivePredictionConnection? _predictionConnection;
  bool _predictionConnectionLoaded = false;

  /// Issue #373: live only while [_predictionConnection] is pending; each
  /// tick re-reads the row so the pending -> active transition is caught
  /// (and published) while the sharer is on this screen showing the code.
  Timer? _pendingPoll;

  /// #544: consecutive [_loadPredictionConnection] failures while the poll
  /// is running. Reset to 0 on any success; once it reaches
  /// [_maxPendingPollFailures] the poll stops hammering a connection that
  /// keeps failing instead of retrying every 15s indefinitely.
  int _pendingPollFailures = 0;
  static const int _maxPendingPollFailures = 3;

  /// #544: per-row busy guards so a mutation's own trigger disables itself
  /// while its RPC is in flight, instead of staying tappable (and, for a
  /// double role-change tap, racing two updates for the same row).
  final Set<String> _revokingUserIds = {};
  final Set<String> _changingRoleUserIds = {};
  final Set<String> _cancellingInviteIds = {};

  /// Issue #472: true while "Delete profile permanently"'s RPC is in
  /// flight, so a second tap (or the two double-confirmation dialogs
  /// reopening) cannot fire a second call.
  bool _deletingProfile = false;

  /// Issue #472: honest, in-place failure copy for a failed delete
  /// (`lib/ui/README.md`'s rule: a delete's own failure renders
  /// `InlineError` right next to the control, not a `SnackBar`). Cleared
  /// on the next attempt.
  String? _deleteProfileError;

  @override
  void initState() {
    super.initState();
    _loadPendingInvites();
    unawaited(_loadPredictionConnection());
  }

  @override
  void dispose() {
    _pendingPoll?.cancel();
    _pendingPoll = null;
    super.dispose();
  }

  Future<void> _loadPredictionConnection() async {
    final service = _predictionService;
    if (service == null) return;
    try {
      final connection = await service.getActiveConnection(
        profileId: widget.profile.id,
      );
      if (!mounted) return;
      final previous = _predictionConnection;
      setState(() {
        _predictionConnection = connection;
        _predictionConnectionLoaded = true;
        // #544: a successful read resets the failure streak, so a
        // transient network blip doesn't count toward the poll's shutoff.
        _pendingPollFailures = 0;
      });
      _syncPendingPoll();
      // Issue #373: the code was just redeemed - publish now, from this
      // (the sharer's) side, so the recipient's first fetch has data.
      if (previous?.pending == true && connection?.pending == false) {
        widget.onPredictionConnectionChanged?.call(widget.profile.id);
      }
    } on PredictionConnectionFailure {
      if (!mounted) return;
      setState(() {
        _predictionConnectionLoaded = true;
        _pendingPollFailures++;
      });
      _syncPendingPoll();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _predictionConnectionLoaded = true;
        _pendingPollFailures++;
      });
      _syncPendingPoll();
    }
  }

  /// Starts the pending poll when the loaded connection is pending and
  /// stops it otherwise (redeemed, revoked, or gone) - one timer at most.
  ///
  /// #544: also stops it once [_pendingPollFailures] reaches
  /// [_maxPendingPollFailures] - a persistently failing read must not hit
  /// the network every [ManageGuardiansScreen.pendingPollInterval] for as
  /// long as the screen stays open. The next manual reload (reopening the
  /// screen, or any action that calls [_loadPredictionConnection] again)
  /// resets the streak and can restart it.
  void _syncPendingPoll() {
    final pending = _predictionConnection?.pending == true;
    final tooManyFailures = _pendingPollFailures >= _maxPendingPollFailures;
    if (pending && !tooManyFailures && _pendingPoll == null) {
      _pendingPoll = Timer.periodic(
        ManageGuardiansScreen.pendingPollInterval,
        (_) => _loadPredictionConnection(),
      );
    } else if (!pending || tooManyFailures) {
      _pendingPoll?.cancel();
      _pendingPoll = null;
    }
  }

  Future<void> _sharePredictions() async {
    final service = _predictionService;
    if (service == null) return;
    await showDialog<void>(
      context: context,
      // #558: once a single-use connection code is generated, the server
      // never stores its raw token again -- a stray tap outside the
      // dialog must not be able to destroy access to it.
      barrierDismissible: false,
      builder: (ctx) => SharePredictionsDialog(
        profileId: widget.profile.id,
        profileName: widget.profile.displayName,
        service: service,
      ),
    );
    if (!mounted) return;
    await _loadPredictionConnection();
    widget.onPredictionConnectionChanged?.call(widget.profile.id);
  }

  Future<void> _revokePredictionConnection() async {
    final service = _predictionService;
    final connection = _predictionConnection;
    if (service == null || connection == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End prediction sharing?'),
        content: const SingleChildScrollView(
          child: Text(
            'They will immediately lose the shared predictions calendar. '
            'You can create a new connection any time.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End sharing'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await service.revokeConnection(connectionId: connection.connectionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prediction sharing ended')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to end sharing. Check connection.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await _loadPredictionConnection();
    widget.onPredictionConnectionChanged?.call(widget.profile.id);
  }

  /// Issue #472: "Delete profile permanently" — a double-confirmation flow
  /// (each step names a different consequence, so the second tap is never
  /// a reflexive re-click of the same dialog) ending in
  /// [ProfileErasureService.deleteProfile]. Split into the two dialog
  /// steps plus [_performDeleteProfile] (the CRAP-gate per-method
  /// complexity cap, the same reason [_revoke] is split from
  /// [_confirmRevoke]/[_performRevoke]).
  Future<void> _deleteProfilePermanently() async {
    final service = widget.profileErasureService;
    if (service == null || _deletingProfile) return;
    if (await _confirmDeleteProfileStep1() != true || !mounted) return;
    if (await _confirmDeleteProfileStep2() != true || !mounted) return;
    await _performDeleteProfile(service);
  }

  Future<bool?> _confirmDeleteProfileStep1() => showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: kRouteDeleteProfileDialog),
    builder: (ctx) => AlertDialog(
      title: Text('Delete ${widget.profile.displayName} permanently?'),
      content: const SingleChildScrollView(
        child: Text(
          'This permanently erases every day entry, care note, and '
          "visit-prep item on this profile, and removes every guardian's "
          'access to it — including your own. Synced copies on every '
          'device are erased too.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        DestructiveButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  Future<bool?> _confirmDeleteProfileStep2() => showDialog<bool>(
    context: context,
    routeSettings:
        const RouteSettings(name: kRouteDeleteProfileFinalConfirmDialog),
    builder: (ctx) => AlertDialog(
      title: const Text('Are you absolutely sure?'),
      content: Text(
        "${widget.profile.displayName}'s history will be gone "
        'permanently, for every guardian on this profile. There is no '
        'undo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        DestructiveButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );

  /// The actual RPC + busy-state + error-surfacing (see
  /// [_deleteProfilePermanently]'s doc comment for why this is split out).
  /// Never removes anything locally itself — [ProfileErasureService
  /// .deleteProfile] only applies the local wipe after its own server call
  /// has already succeeded, so a failure here (including offline) leaves
  /// this device's copy of the profile untouched.
  Future<void> _performDeleteProfile(ProfileErasureService service) async {
    setState(() {
      _deletingProfile = true;
      _deleteProfileError = null;
    });
    try {
      await service.deleteProfile(profileId: widget.profile.id);
      // Success: the profile is gone server-side and locally. This screen
      // names a profile that no longer exists, so it must not stay open —
      // the caller (profile picker / shared chip) already reacts to the
      // profile vanishing from ProfilesRepository.watch() on its own.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _deletingProfile = false;
          _deleteProfileError = _deleteProfileErrorMessage(e);
        });
      }
    }
  }

  String _deleteProfileErrorMessage(Object error) {
    if (error is ProfileErasureNetworkFailure) {
      return "Can't delete while offline. Check your connection and try "
          'again.';
    }
    if (error is ProfileErasureUnauthorizedFailure) {
      return 'You do not have permission for this action.';
    }
    return 'Failed to delete profile. Check connection and try again.';
  }

  void _loadPendingInvites() {
    setState(() {
      _pendingInvitesFuture = widget.sharingService.listPendingInvites(
        widget.profile.id,
      );
    });
  }

  /// Every guardian row for this profile, any status; null means the
  /// initial pull hasn't landed locally yet (#13). Nothing writes a local
  /// guardian row when a profile is created, so a freshly created or
  /// not-yet-synced profile has zero rows here — that must not be read as
  /// "synced, and the caller isn't a manager" (see [_callerRoleOf] and the
  /// FAB gate below, which only hide controls once rows have actually
  /// arrived).
  Stream<List<ProfileGuardian>?> get _guardianRows =>
      watchGuardiansForProfileSafely(
        widget.guardiansRepository,
        widget.profile.id,
      ).map((rows) => rows.isEmpty ? null : rows);

  List<ProfileGuardian> _acceptedOf(List<ProfileGuardian>? rows) =>
      (rows ?? const [])
          .where((g) => g.status == GuardianStatus.accepted)
          .toList();

  /// The caller's own accepted role on this profile, or null when the
  /// caller is not an active guardian, is unknown, or [rows] hasn't
  /// synced yet.
  GuardianRole? _callerRoleOf(List<ProfileGuardian>? rows) {
    if (rows == null) return null;
    final uid = widget.currentUserId;
    if (uid == null) return null;
    for (final g in _acceptedOf(rows)) {
      if (g.userId == uid) return g.role;
    }
    return null;
  }

  /// R3/R4 revocation authority: a primary guardian may leave only when
  /// another accepted primary guardian remains — the server rejects a
  /// sole primary guardian's self-leave with
  /// `object_not_in_prerequisite_state` (#5); any other caller may always
  /// leave; the primary guardian may revoke anyone; a co-parent may
  /// revoke caregivers and viewers only.
  bool _canRevoke(
    ProfileGuardian guardian,
    GuardianRole? callerRole,
    List<ProfileGuardian> activeGuardians,
  ) {
    if (callerRole == null) return false;
    final isSelf = guardian.userId == widget.currentUserId;
    if (isSelf) {
      if (callerRole != GuardianRole.primaryGuardian) return true;
      return activeGuardians.any(
        (g) =>
            g.role == GuardianRole.primaryGuardian &&
            g.userId != widget.currentUserId,
      );
    }
    if (callerRole == GuardianRole.primaryGuardian) return true;
    if (callerRole == GuardianRole.coParent) {
      return guardian.role != GuardianRole.primaryGuardian &&
          guardian.role != GuardianRole.coParent;
    }
    return false;
  }

  /// Best-effort accurate messaging for the self-leave-as-sole-primary
  /// race (#5): the button is already hidden once the client knows the
  /// caller is the only accepted primary guardian (see [_canRevoke]), but
  /// a concurrent revoke on another device can still make that true
  /// between the tap and this RPC call landing. [SharingFailure] has no
  /// dedicated case for the server's `object_not_in_prerequisite_state`
  /// here — adding one belongs to the sharing service, which this pass
  /// doesn't own — so this infers the scenario from context instead of
  /// the raw error code: only a self-leave attempt by a primary guardian
  /// can hit that specific rejection.
  String _revokeErrorMessage(Object error, ProfileGuardian guardian) {
    final isSelfPrimaryLeave =
        guardian.userId == widget.currentUserId &&
        guardian.role == GuardianRole.primaryGuardian;
    if (isSelfPrimaryLeave) {
      return "You're now the only primary guardian, so you can't leave. "
          'Add another primary guardian first, then try again.';
    }
    if (error is SharingUnauthorizedFailure) {
      return 'You do not have permission for this action.';
    }
    return 'Failed to remove guardian. Check connection.';
  }

  Future<void> _revoke(ProfileGuardian guardian) async {
    // #544: blocks a second tap while this guardian's own revoke is
    // in flight (the trigger also disables itself - see [_guardianTrailing]
    // - this is the belt-and-suspenders guard against a race between that
    // rebuild and a very fast second tap).
    if (_revokingUserIds.contains(guardian.userId)) return;
    final confirm = await _confirmRevoke(guardian);
    if (confirm != true || !mounted) return;
    await _performRevoke(guardian);
  }

  /// Split out of [_revoke] (issue #556 review: the CRAP gate's per-method
  /// complexity cap) so the confirmation dialog's own branching (which
  /// caller is leaving vs. removing someone else) isn't counted against
  /// [_revoke] itself.
  Future<bool?> _confirmRevoke(ProfileGuardian guardian) {
    final roleLabel = guardianRoleLabel(
      AppLocalizations.of(context),
      guardian.role,
    );
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${guardian.displayName ?? roleLabel}?'),
        content: SingleChildScrollView(
          child: Text(
            guardian.userId == widget.currentUserId
                ? 'You will leave this profile and no longer receive updates or sync its entries.'
                : 'This guardian will lose access to ${widget.profile.displayName}\'s calendar and entries.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  /// See [_confirmRevoke]'s doc comment: the actual RPC + busy-state +
  /// error-surfacing, split out of [_revoke] for the same reason.
  Future<void> _performRevoke(ProfileGuardian guardian) async {
    setState(() => _revokingUserIds.add(guardian.userId));
    try {
      await widget.sharingService.revokeGuardian(
        profileId: widget.profile.id,
        targetUserId: guardian.userId,
      );
      if (mounted) {
        final roleLabel = guardianRoleLabel(
          AppLocalizations.of(context),
          guardian.role,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${guardian.displayName ?? roleLabel}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_revokeErrorMessage(e, guardian))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _revokingUserIds.remove(guardian.userId));
      }
    }
  }

  void _openInviteDialog() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        routeSettings: const RouteSettings(name: kRouteInviteGuardianSheet),
        // #558: once a single-use invite link is generated, the server never
        // stores its raw token again -- a stray tap outside the dialog must
        // not be able to destroy access to it.
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => InviteGuardianDialog(
          profileId: widget.profile.id,
          profileName: widget.profile.displayName,
          sharingService: widget.sharingService,
        ),
        // A newly created invitation should appear in the pending list as
        // soon as the dialog closes, whether the operator created one or
        // just dismissed the dialog - re-listing is cheap and harmless
        // either way.
      ).then((_) {
        if (mounted) _loadPendingInvites();
      }),
    );
  }

  /// R3 invitation-cancellation ladder, mirroring [_canRevoke]'s guardian
  /// ladder: the primary guardian may cancel any invitation on the
  /// profile; a co-parent may cancel a caregiver or viewer invitation, but
  /// never a co_parent one - only the primary guardian can create a
  /// co_parent invitation in the first place (`create_guardian_invitation`
  /// forbids a co-parent from inviting a co-parent), so a co-parent could
  /// never have created one to cancel. A caregiver or viewer may cancel
  /// nothing.
  bool _canCancelInvite(PendingInvite invite, GuardianRole? callerRole) {
    if (callerRole == GuardianRole.primaryGuardian) return true;
    if (callerRole == GuardianRole.coParent) {
      return invite.role != GuardianRole.coParent;
    }
    return false;
  }

  /// Relative time remaining until [expiresAt], clamped at "expired" rather
  /// than rendering a negative duration for a stale load (Q2/U3 test list).
  String _expiryLabel(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return 'expired';
    if (remaining.inHours >= 1) return 'expires in ${remaining.inHours}h';
    final minutes = remaining.inMinutes;
    return 'expires in ${minutes < 1 ? 1 : minutes}m';
  }

  Future<void> _cancelInvite(PendingInvite invite) async {
    // #544: blocks a second tap while this invitation's own cancel is in
    // flight.
    if (_cancellingInviteIds.contains(invite.invitationId)) return;
    final l10n = AppLocalizations.of(context);
    final inviteRoleLabel = guardianRoleLabel(l10n, invite.role);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Cancel invitation for ${invite.recipientLabel?.isNotEmpty == true ? invite.recipientLabel! : inviteRoleLabel}?',
        ),
        content: const SingleChildScrollView(
          child: Text(
            'The invite link will stop working immediately. You can send a new one any time.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Invitation'),
          ),
          DestructiveButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel Invitation'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _cancellingInviteIds.add(invite.invitationId));
    try {
      final outcome = await widget.sharingService.cancelInvite(
        invite.invitationId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inviteCancellationCopy(AppLocalizations.of(context), outcome),
          ),
        ),
      );
      // Every outcome is terminal for this row (R5): refresh regardless, so
      // an already-accepted invitation never lingers as a stale pending
      // row - the accepted guardian itself shows up via the live guardian
      // stream, which needs no action here.
      _loadPendingInvites();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to cancel invitation. Check connection.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _cancellingInviteIds.remove(invite.invitationId));
      }
    }
  }

  Widget _pendingInvitesSection(
    List<ProfileGuardian>? rows,
    GuardianRole? callerRole,
  ) {
    final theme = Theme.of(context);
    // Mirrors the FAB gate's null-vs-empty discipline: rows still null
    // (not yet synced) must not collapse this into "not a manager".
    final knownNonManager =
        rows != null && callerRole?.canManageGuardians != true;
    if (knownNonManager) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<PendingInvite>>(
      future: _pendingInvitesFuture,
      builder: (context, snapshot) {
        Widget content;
        if (snapshot.connectionState == ConnectionState.waiting) {
          content = const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        } else if (snapshot.hasError) {
          content = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: InlineError(
              key: const ValueKey('pending-invites-error'),
              message: 'Could not load pending invitations.',
              onRetry: _loadPendingInvites,
            ),
          );
        } else {
          final invites = snapshot.data ?? const [];
          content = invites.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'No pending invitations',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final invite in invites)
                      _pendingInviteTile(invite, callerRole),
                  ],
                );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Pending invitations',
                style: theme.textTheme.titleSmall,
              ),
            ),
            content,
          ],
        );
      },
    );
  }

  Widget _pendingInviteTile(PendingInvite invite, GuardianRole? callerRole) {
    final l10n = AppLocalizations.of(context);
    final roleLabel = guardianRoleLabel(l10n, invite.role);
    final label = invite.recipientLabel?.isNotEmpty == true
        ? invite.recipientLabel!
        : roleLabel;
    // Issue #362: a recently expired invitation renders as a distinct row
    // state - an `Expired` subtitle (never a negative countdown) with a
    // Resend action that re-opens the existing invite flow, then reloads.
    if (invite.isExpiredAt(DateTime.now().toUtc())) {
      return ListTile(
        key: ValueKey('pending-invite-${invite.invitationId}'),
        leading: const Icon(Icons.mail_outline),
        title: Text(label),
        subtitle: Text('$roleLabel • Expired'),
        trailing: _canCancelInvite(invite, callerRole)
            ? TextButton(
                onPressed: _openInviteDialog,
                child: const Text('Resend'),
              )
            : null,
      );
    }
    // #544: disables the cancel trigger while this invite's own cancel is
    // in flight, instead of leaving it tappable through the whole RPC.
    final cancelling = _cancellingInviteIds.contains(invite.invitationId);
    return ListTile(
      key: ValueKey('pending-invite-${invite.invitationId}'),
      leading: const Icon(Icons.mail_outline),
      title: Text(label),
      subtitle: Text('$roleLabel • ${_expiryLabel(invite.expiresAt)}'),
      trailing: _canCancelInvite(invite, callerRole)
          ? (cancelling
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: ValueKey('cancel-invite-${invite.invitationId}'),
                    icon: const Icon(Icons.cancel_outlined),
                    tooltip: l10n.manageGuardiansCancelInviteTooltip,
                    onPressed: () => _cancelInvite(invite),
                  ))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final notificationPreferencesService =
        widget.notificationPreferencesService;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.profile.displayName} Guardians'),
        // R26: the transfer-ownership entry point is offered only to the
        // profile's accepted primary guardian, and only when an
        // OwnershipTransferService is actually configured on this build.
        actions: [
          // Issue #139: contextual entry point to the guardian-roles card.
          IconButton(
            key: const ValueKey('guardians-help-action'),
            tooltip: l10n.manageGuardiansAboutRolesTooltip,
            icon: const Icon(Icons.help_outline),
            onPressed: () =>
                showHelpCardSheet(context, HelpCards.guardianRoles),
          ),
          if (widget.activityRepository != null)
            ActivityFeedButton(
              profile: widget.profile,
              repository: widget.activityRepository!,
            ),
          StreamBuilder<List<ProfileGuardian>?>(
            stream: _guardianRows,
            builder: (context, snapshot) {
              final rows = snapshot.data;
              final callerRole = _callerRoleOf(rows);
              final canTransfer =
                  callerRole == GuardianRole.primaryGuardian &&
                  widget.ownershipTransferService != null;
              if (!canTransfer) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: l10n.manageGuardiansTransferOwnershipTooltip,
                icon: const Icon(Icons.compare_arrows),
                onPressed: () => Navigator.of(context).push(
                  buildNamedRoute<void>(
                    name: kRouteTransferOwnershipScreen,
                    builder: (_) => TransferOwnershipScreen(
                      profile: widget.profile,
                      service: widget.ownershipTransferService!,
                    ),
                  ),
                ),
              );
            },
          ),
          if (notificationPreferencesService != null)
            IconButton(
              key: const ValueKey('notifications-action'),
              tooltip: l10n.manageGuardiansNotificationsTooltip,
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(
                buildNamedRoute<void>(
                  name: kRouteNotificationPreferencesScreen,
                  builder: (_) => NotificationPreferencesScreen(
                    profile: widget.profile,
                    preferencesService: notificationPreferencesService,
                  ),
                ),
              ),
            ),
        ],
      ),
      // U8: only the primary guardian and co-parents can invite; the
      // server enforces it too, so the button is not even offered. Rows
      // still null (#13, not yet pulled) leaves the FAB visible — the
      // same default as before role gating existed — until we actually
      // know the caller isn't a manager.
      // A nested StreamBuilder keeps the same proven-settling structure
      // as the body below.
      floatingActionButton: StreamBuilder<List<ProfileGuardian>?>(
        stream: _guardianRows,
        builder: (context, snapshot) {
          final rows = snapshot.data;
          final callerRole = _callerRoleOf(rows);
          final knownNonManager =
              rows != null && callerRole?.canManageGuardians != true;
          if (knownNonManager) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: _openInviteDialog,
            icon: const Icon(Icons.person_add),
            label: const Text('Invite guardian'),
          );
        },
      ),
      body: StreamBuilder<List<ProfileGuardian>?>(
        stream: _guardianRows,
        builder: (context, snapshot) {
          // #544: the mapped stream legitimately emits null for "no rows
          // yet synced" (see [_guardianRows]'s doc comment), so
          // `snapshot.data == null` cannot distinguish that from "no
          // emission has landed at all" -- both look identical. Only
          // `ConnectionState.waiting` (true until the *first* event of any
          // kind) means genuinely still loading; that is what keeps "No
          // caregivers linked yet" from flashing before the first real
          // answer arrives. This gates only the guardian-list portion
          // below (not the whole body/return) so the pending-invitations
          // `FutureBuilder` still mounts on the very first frame and
          // attaches to `_pendingInvitesFuture` immediately -- delaying
          // that mount until this stream's first emission would leave the
          // future briefly unobserved and risk an unhandled-error report
          // if it rejects before anything is listening.
          final stillLoading =
              snapshot.connectionState == ConnectionState.waiting;
          final rows = snapshot.data;
          final activeGuardians = _acceptedOf(rows);
          final callerRole = _callerRoleOf(rows);

          final guardianList = stillLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : activeGuardians.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No guardians linked yet',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Invite another guardian to sync and share tracking.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  // U3: the pending-invitations section sits below this
                  // list, in the same scrollable column - shrinkWrap lets
                  // this list size to its own content inside that outer
                  // scroll view instead of claiming unbounded height.
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: activeGuardians.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _guardianTile(
                    context,
                    activeGuardians[index],
                    callerRole,
                    activeGuardians,
                  ),
                );

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                guardianList,
                _pendingInvitesSection(rows, callerRole),
                _predictionSection(rows, callerRole),
                _dangerZoneSection(callerRole),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Issue #151: the predictions-only sharing section. Hidden entirely
  /// when no PredictionConnectionService is configured (R26's null-gating
  /// discipline); the create affordance shows only for the profile's
  /// accepted primary guardian - the server enforces both again.
  Widget _predictionSection(
    List<ProfileGuardian>? rows,
    GuardianRole? callerRole,
  ) {
    final service = _predictionService;
    if (service == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final isPrimary = callerRole == GuardianRole.primaryGuardian;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Predictions-only sharing',
            style: theme.textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Shares estimated period, fertile, ovulation, and PMS days on a '
            'read-only calendar - never notes or logs. One connection.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // Issue #373: PRIVACY.md - minor profiles are never shared. The
        // server refuses the create RPC too; this only keeps the
        // affordance off a screen where it could never succeed.
        if (widget.profile.isMinor)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              "Prediction sharing is not available for a minor's profile.",
              key: const ValueKey('share-predictions-minor'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else if (!_predictionConnectionLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_predictionConnection == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: isPrimary
                ? OutlinedButton.icon(
                    key: const ValueKey('share-predictions'),
                    onPressed: _sharePredictions,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Share predictions only...'),
                  )
                : Text(
                    'Only the primary guardian can share predictions.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          )
        else
          _predictionTile(_predictionConnection!, isPrimary),
      ],
    );
  }

  Widget _predictionTile(
    ActivePredictionConnection connection,
    bool isPrimary,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final title = connection.pending
        ? (connection.recipientLabel?.isNotEmpty == true
              ? connection.recipientLabel!
              : 'Waiting for code redemption')
        : (connection.recipientLabel?.isNotEmpty == true
              ? connection.recipientLabel!
              : 'Sharing predictions');
    return ListTile(
      key: const ValueKey('prediction-connection-tile'),
      leading: Icon(connection.pending ? Icons.schedule : Icons.calendar_month),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(title),
          if (connection.pending)
            Text(
              'pending',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      subtitle: Text(
        connection.pending
            ? _expiryLabel(connection.expiresAt)
            : 'Phases-only calendar • not a guardian',
      ),
      trailing: isPrimary
          ? IconButton(
              key: const ValueKey('revoke-prediction-connection'),
              icon: const Icon(Icons.link_off),
              tooltip: l10n.manageGuardiansEndSharingTooltip,
              onPressed: _revokePredictionConnection,
            )
          : null,
    );
  }

  /// Issue #472: "Delete profile permanently" — hidden entirely when no
  /// [ProfileErasureService] is configured (R26's null-gating discipline,
  /// same shape as [_predictionSection]) or when the caller's accepted
  /// role is not (or not yet known to be) `primary_guardian`. AC: "Non-
  /// primary guardians (co_parent, caregiver, viewer) never see the
  /// delete action" — `callerRole` starts null until the guardian rows
  /// have synced (#13), so a not-yet-resolved caller also sees nothing
  /// here, the safe default for an irreversible action (unlike
  /// [_pendingInvitesSection]'s fail-open menu, which only ever exposes a
  /// reversible cancel).
  Widget _dangerZoneSection(GuardianRole? callerRole) {
    final service = widget.profileErasureService;
    if (service == null || callerRole != GuardianRole.primaryGuardian) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Danger zone',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Permanently erases this profile and everything logged on it, '
            'for every guardian. This cannot be undone.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: DestructiveButton.icon(
              key: const ValueKey('delete-profile-permanently'),
              onPressed:
                  _deletingProfile ? null : _deleteProfilePermanently,
              icon: _deletingProfile
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onError,
                      ),
                    )
                  : const Icon(Icons.delete_forever),
              label: const Text('Delete profile permanently'),
            ),
          ),
        ),
        if (_deleteProfileError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: InlineError(
              key: const ValueKey('delete-profile-error'),
              message: _deleteProfileError!,
            ),
          ),
      ],
    );
  }

  /// Role-change options for [guardian]'s row (Issue #127): the assignable
  /// roles [callerRole] may move them to. Empty means no role control is
  /// shown - the server re-checks the same ladder, so this only decides
  /// what the UI offers.
  List<GuardianRole> _allowedNewRoles(
    ProfileGuardian guardian,
    GuardianRole? callerRole,
  ) => allowedNewRoles(
    callerRole: callerRole,
    target: guardian,
    currentUserId: widget.currentUserId,
  );

  String _roleChangeErrorMessage(Object error) {
    if (error is SharingUnauthorizedFailure) {
      return 'You do not have permission for this action.';
    }
    return 'Failed to update role. Check connection.';
  }

  Future<void> _changeRole(
    ProfileGuardian guardian,
    GuardianRole newRole,
  ) async {
    // #544: blocks a second selection while this guardian's own role
    // change is in flight.
    if (_changingRoleUserIds.contains(guardian.userId)) return;
    final l10n = AppLocalizations.of(context);
    final currentRoleLabel = guardianRoleLabel(l10n, guardian.role);
    final newRoleLabel = guardianRoleLabel(l10n, newRole);
    final name = guardian.displayName?.isNotEmpty == true
        ? guardian.displayName!
        : currentRoleLabel;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change role to $newRoleLabel?'),
        content: SingleChildScrollView(
          child: Text(
            '$name currently has $currentRoleLabel access. '
            '${roleChangeConsequence(guardian.role, newRole)} '
            'No new invitation is needed — the new role applies on their '
            'next sync.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Change role'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _changingRoleUserIds.add(guardian.userId));
    try {
      await widget.sharingService.updateGuardianRole(
        profileId: widget.profile.id,
        targetUserId: guardian.userId,
        newRole: newRole,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Role updated to $newRoleLabel')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_roleChangeErrorMessage(e))));
      }
    } finally {
      if (mounted) {
        setState(() => _changingRoleUserIds.remove(guardian.userId));
      }
    }
  }

  Widget _guardianTile(
    BuildContext context,
    ProfileGuardian guardian,
    GuardianRole? callerRole,
    List<ProfileGuardian> activeGuardians,
  ) {
    final theme = Theme.of(context);
    final roleLabel = guardianRoleLabel(
      AppLocalizations.of(context),
      guardian.role,
    );
    final isMe =
        widget.currentUserId != null && guardian.userId == widget.currentUserId;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isMe
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          isMe ? Icons.person : Icons.family_restroom,
          color: isMe
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      // #138 (AC4): a Wrap, not a Row — the "(you)" suffix and the name are
      // one announcement, and at 200% text scale they flow to a second
      // line instead of overflowing the tile.
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(
            guardian.displayName?.isNotEmpty == true
                ? guardian.displayName!
                : roleLabel,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isMe)
            Text(
              '(you)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      subtitle: Text(roleLabel),
      trailing: _guardianTrailing(
        context,
        guardian,
        callerRole,
        activeGuardians,
      ),
    );
  }

  /// The trailing controls for a guardian row: the role-change menu (Issue
  /// #127) when the caller may move this guardian to another role, plus the
  /// existing revocation control. Either may be absent independently.
  Widget? _guardianTrailing(
    BuildContext context,
    ProfileGuardian guardian,
    GuardianRole? callerRole,
    List<ProfileGuardian> activeGuardians,
  ) {
    final newRoles = _allowedNewRoles(guardian, callerRole);
    final canRevoke = _canRevoke(guardian, callerRole, activeGuardians);
    if (newRoles.isEmpty && !canRevoke) return null;
    final l10n = AppLocalizations.of(context);
    final isMe =
        widget.currentUserId != null && guardian.userId == widget.currentUserId;
    // #544: each trigger disables itself while its own mutation for this
    // row is in flight, so a slow network never leaves the control
    // tappable through the whole RPC.
    final changingRole = _changingRoleUserIds.contains(guardian.userId);
    final revoking = _revokingUserIds.contains(guardian.userId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (newRoles.isNotEmpty)
          changingRole
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : PopupMenuButton<GuardianRole>(
                  key: ValueKey('change-role-${guardian.userId}'),
                  tooltip: l10n.manageGuardiansChangeRoleTooltip,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  onSelected: (role) => _changeRole(guardian, role),
                  itemBuilder: (ctx) => [
                    for (final role in newRoles)
                      PopupMenuItem<GuardianRole>(
                        value: role,
                        child: Text(guardianRoleLabel(l10n, role)),
                      ),
                  ],
                ),
        if (canRevoke)
          revoking
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  key: ValueKey('revoke-${guardian.userId}'),
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: isMe
                      ? l10n.manageGuardiansLeaveProfileTooltip
                      : l10n.manageGuardiansRemoveCaregiverTooltip,
                  onPressed: () => _revoke(guardian),
                ),
      ],
    );
  }
}
