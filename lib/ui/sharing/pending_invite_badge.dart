/// Outstanding-invitation badge for use outside Manage Guardians (Issue #126).
///
/// Fetches [SharingService.listPendingInvites] once (and again whenever
/// [profileId] or [refreshToken] changes) and renders a small count badge
/// when at least one invitation is outstanding. Live invitations keep the
/// count badge; when only recently expired invitations remain (issue #362)
/// the badge renders error-colored with an "N invitation(s) expired"
/// tooltip instead. Pending invitations are
/// deliberately never synced locally, so this badge needs connectivity to
/// be accurate: any failure — including offline — renders nothing, never
/// an error state and never a spinner, and never blocks its screen. Do not
/// render this widget for a viewer/caregiver caller (see
/// [SharingProfileInfo.canShowPendingBadge]); it takes no role itself so
/// it stays a pure fetch-and-render seam.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';

class PendingInviteBadge extends StatefulWidget {
  const PendingInviteBadge({
    super.key,
    required this.profileId,
    required this.sharingService,
    this.refreshToken = 0,
  });

  final String profileId;
  final SharingService sharingService;

  /// Bumped by the owning screen when invitations may have changed (e.g.
  /// returning from Manage Guardians after a cancel), refetching the badge.
  final int refreshToken;

  @override
  State<PendingInviteBadge> createState() => _PendingInviteBadgeState();
}

class _PendingInviteBadgeState extends State<PendingInviteBadge> {
  late Future<List<PendingInvite>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(PendingInviteBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.sharingService != widget.sharingService) {
      _future = _load();
    }
  }

  /// Offline-honest load: any failure resolves to an empty list (no badge)
  /// rather than an error state.
  Future<List<PendingInvite>> _load() async {
    try {
      return await widget.sharingService.listPendingInvites(widget.profileId);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<PendingInvite>>(
      future: _future,
      builder: (context, snapshot) {
        final invites = snapshot.data ?? const <PendingInvite>[];
        if (snapshot.connectionState == ConnectionState.waiting ||
            invites.isEmpty) {
          return const SizedBox.shrink();
        }
        // Issue #362: live invitations keep the current count badge; when
        // only expired invitations remain, render a visually distinct
        // error-colored badge so an aged-out invite reads as expired.
        // Issue #304: one wall-clock read per build, passed into
        // `isExpiredAt` -- `lib/domain` no longer reads `DateTime.now()`
        // itself.
        final now = DateTime.now().toUtc();
        final live = invites.where((i) => !i.isExpiredAt(now)).toList();
        if (live.isNotEmpty) {
          return Tooltip(
            message: l10n.sharingPendingInviteBadgePendingCount(live.length),
            child: Badge(
              label: Text('${live.length}'),
              child: const Icon(Icons.mail_outline),
            ),
          );
        }
        final expired = invites.where((i) => i.isExpiredAt(now)).toList();
        return Tooltip(
          message: l10n.sharingPendingInviteBadgeExpiredCount(expired.length),
          child: Badge(
            backgroundColor: Theme.of(context).colorScheme.error,
            label: Text('${expired.length}'),
            child: const Icon(Icons.mail_outline),
          ),
        );
      },
    );
  }
}
