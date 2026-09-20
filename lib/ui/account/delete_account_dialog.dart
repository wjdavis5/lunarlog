/// The account-deletion confirmation (Issue #17, Unit U6; R2). Split out of
/// `account_section.dart` because "Export first" must keep the dialog open
/// across an asynchronous export instead of popping it (the operator must
/// see the file exists before anything is destroyed) - state a plain
/// `AlertDialog` builder cannot hold, unlike `_signOutEverywhere`'s two-
/// action confirmation.
///
/// Issue #533: deleting your account cascades every profile you *own*
/// (`supabase/migrations/20260905110000_account_deletion.sql`) - taking any
/// co-guardian's access, and any minor's whole history, with it - while
/// entries you logged as a guardian on someone else's profile are kept and
/// re-attributed rather than deleted
/// (`supabase/migrations/20260906120000_account_deletion_final_rehome.sql`).
/// Neither consequence was previously disclosed, so this dialog now loads
/// the "blast radius" (which profiles the caller owns, and how many other
/// accepted guardians each has) before its confirm button is enabled, names
/// it in the copy, requires an extra acknowledgement checkbox whenever a
/// shared owned profile exists, and offers "Transfer ownership first" as a
/// way out of that specific case (reusing the existing
/// `TransferOwnershipScreen`, not a new flow).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/profile.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/repositories/profile_guardians_repository.dart';
import '../../domain/repositories/profiles_repository.dart';
import '../../domain/sharing/ownership_transfer_service.dart';
import '../../domain/sharing/sharing_overview.dart';
import '../../observability/route_names.dart';
import '../components/inline_error.dart';
import '../sharing/transfer_ownership_screen.dart';
import 'auth_controller.dart';

/// What the operator chose. `null` (from [showDeleteAccountDialog]) means
/// the dialog was dismissed some other way (e.g. the system back button);
/// callers treat that exactly like [cancel].
enum DeleteAccountDecision { cancel, delete }

/// One profile the caller owns, and how many *other* accepted guardians
/// would lose access to it if the caller's account were deleted (#533).
class _OwnedProfileImpact {
  const _OwnedProfileImpact({
    required this.profile,
    required this.otherGuardianCount,
  });

  final Profile profile;
  final int otherGuardianCount;
}

/// The account-deletion blast radius beyond the caller's own rows (#533):
/// every profile the caller owns - deleted outright by the server-side
/// cascade, see `supabase/migrations/20260905110000_account_deletion.sql`
/// around lines 126-131 - and, for each, how many other accepted guardians
/// would lose access. Loaded once per dialog open (a one-shot confirmation,
/// not a screen, so this is a plain [Future] rather than a live
/// subscription like `SharingOverviewController` uses for the Settings
/// list).
class _DeleteAccountBlastRadius {
  const _DeleteAccountBlastRadius({this.ownedProfiles = const []});

  static const empty = _DeleteAccountBlastRadius();

  final List<_OwnedProfileImpact> ownedProfiles;

  int get totalOtherGuardians =>
      ownedProfiles.fold(0, (sum, p) => sum + p.otherGuardianCount);

  /// Whether any owned profile has another accepted guardian - the case
  /// that requires the extra acknowledgement checkbox and offers "Transfer
  /// ownership first" below.
  bool get hasSharedOwnedProfile => totalOtherGuardians > 0;

  /// The first owned, shared profile, or null. "Transfer ownership first"
  /// targets this one; an account that owns more than one such profile can
  /// transfer the rest afterwards from Manage Guardians.
  Profile? get firstSharedOwnedProfile {
    for (final impact in ownedProfiles) {
      if (impact.otherGuardianCount > 0) return impact.profile;
    }
    return null;
  }
}

/// Reads the profiles and guardian repositories from [context] (the same
/// `Provider`/`context.read` DI this file's parent screen,
/// `account_section.dart`, already uses) and computes
/// [_DeleteAccountBlastRadius]. Every read happens before the first `await`
/// (`use_build_context_synchronously`), matching `_runExport`'s own
/// discipline in `account_section.dart`. An unconfigured build (no
/// [ProfilesRepository] provided) degrades to [_DeleteAccountBlastRadius.empty]
/// - the plain flow - rather than failing; a missing
/// [ProfileGuardiansRepository] or a failed per-profile lookup degrades the
/// same way *for that profile only*, per the app's existing fail-open rule
/// for unknown guardian state (never label someone's own profile as shared
/// on missing data).
Future<_DeleteAccountBlastRadius> _loadBlastRadius(BuildContext context) async {
  final profilesRepository = context.read<ProfilesRepository?>();
  if (profilesRepository == null) return _DeleteAccountBlastRadius.empty;
  final guardiansRepository = context.read<ProfileGuardiansRepository?>();
  final currentUserId = context.read<AuthController?>()?.currentUserId;

  final profiles = await profilesRepository.list();
  if (profiles.isEmpty) return _DeleteAccountBlastRadius.empty;

  final owned = <_OwnedProfileImpact>[];
  for (final profile in profiles) {
    var guardians = const <ProfileGuardian>[];
    if (guardiansRepository != null) {
      try {
        guardians = await guardiansRepository.getForProfile(profile.id);
      } catch (_) {
        guardians = const [];
      }
    }
    final info = SharingProfileInfo.fromGuardians(guardians, currentUserId);
    if (info.group != ProfileSharingGroup.owned) continue;
    final otherGuardianCount = guardians
        .where(
          (g) =>
              g.status == GuardianStatus.accepted && g.userId != currentUserId,
        )
        .length;
    owned.add(
      _OwnedProfileImpact(
        profile: profile,
        otherGuardianCount: otherGuardianCount,
      ),
    );
  }
  return _DeleteAccountBlastRadius(ownedProfiles: owned);
}

/// The "This will also permanently delete ..." line (#533), phrased along
/// the lines the issue itself suggests, e.g. "This will also permanently
/// delete 2 profiles you own (Maya, Ada) and remove access for 1 other
/// guardian."
String _blastRadiusCopy(_DeleteAccountBlastRadius radius) {
  final names = [for (final p in radius.ownedProfiles) p.profile.displayName];
  final profileWord = names.length == 1 ? 'profile' : 'profiles';
  final buffer = StringBuffer(
    'This will also permanently delete ${names.length} $profileWord you '
    'own (${names.join(', ')})',
  );
  final otherGuardians = radius.totalOtherGuardians;
  if (otherGuardians > 0) {
    final guardianWord = otherGuardians == 1 ? 'guardian' : 'guardians';
    buffer.write(' and remove access for $otherGuardians other $guardianWord');
  }
  buffer.write('.');
  return buffer.toString();
}

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.onExport});

  /// Runs the export (Issue #17 U5) and rethrows on failure so this dialog
  /// can show its own inline error without closing.
  final Future<void> Function() onExport;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  bool _exporting = false;
  String? _exportError;

  /// #533: unchecked by default whenever it is offered (any owned profile
  /// is shared) - the confirm button stays disabled until the operator
  /// actively acknowledges the extra consequence.
  bool _acknowledged = false;

  late final Future<_DeleteAccountBlastRadius> _blastRadius;

  @override
  void initState() {
    super.initState();
    _blastRadius = _loadBlastRadius(context);
  }

  Future<void> _handleExport() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      await widget.onExport();
    } catch (error) {
      if (mounted) {
        setState(
          () => _exportError = 'Could not export your data. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// #533: pops this dialog as a cancelled deletion, then pushes the
  /// existing `TransferOwnershipScreen` for the first owned, shared
  /// profile - reusing that flow/route rather than building a new one.
  /// A no-op if the blast radius names no such profile, or if no
  /// [OwnershipTransferService] is configured on this build.
  void _handleTransferOwnership(_DeleteAccountBlastRadius blastRadius) {
    final profile = blastRadius.firstSharedOwnedProfile;
    final service = context.read<OwnershipTransferService?>();
    if (profile == null || service == null) return;
    final navigator = Navigator.of(context);
    navigator.pop(DeleteAccountDecision.cancel);
    navigator.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: kRouteTransferOwnershipScreen),
        builder: (_) =>
            TransferOwnershipScreen(profile: profile, service: service),
      ),
    );
  }

  /// #533: gates the destructive confirm action on (a) no export in flight,
  /// (b) the blast radius having actually loaded (never enabled during the
  /// brief initial load - the whole point is to enumerate it *before* the
  /// button is enabled), and (c) the acknowledgement checkbox when the
  /// blast radius includes a shared owned profile.
  bool _confirmEnabled(_DeleteAccountBlastRadius? blastRadius) {
    if (_exporting) return false;
    if (blastRadius == null) return false;
    if (blastRadius.hasSharedOwnedProfile && !_acknowledged) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exportError = _exportError;
    return PopScope(
      // #17 P1 fix: block the hardware-back/system-pop path while an export
      // is in flight, alongside the button guards below and
      // showDeleteAccountDialog's barrierDismissible: false - together
      // these mean the dialog cannot go away by any route until the export
      // has actually finished, so this State is guaranteed still mounted
      // when _handleExport's own `if (mounted)` checks run, and a race
      // between "Delete" and an in-flight export can no longer happen.
      canPop: !_exporting,
      child: FutureBuilder<_DeleteAccountBlastRadius>(
        future: _blastRadius,
        builder: (context, snapshot) {
          final blastRadius = snapshot.data;
          return AlertDialog(
            title: const Text('Delete account?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently removes the server rows for this account, '
                    'the account itself, and this device\'s local data. This '
                    'cannot be undone.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Entries you logged as a guardian on someone else\'s '
                    'profile are kept and re-attributed to its owner, not '
                    'deleted. Apple Health / Health Connect writes this '
                    'device already made stay in the device\'s own health '
                    'store - account deletion does not remove them.',
                  ),
                  if (blastRadius != null &&
                      blastRadius.ownedProfiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _blastRadiusCopy(blastRadius),
                      key: const ValueKey('account-delete-blast-radius'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (blastRadius != null &&
                      blastRadius.hasSharedOwnedProfile) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const ValueKey('account-delete-ack-checkbox'),
                      value: _acknowledged,
                      onChanged: _exporting
                          ? null
                          : (checked) => setState(
                              () => _acknowledged = checked ?? false,
                            ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'I understand this removes access for other '
                        'guardians and deletes any minor profiles I own.',
                      ),
                    ),
                  ],
                  if (exportError != null) ...[
                    const SizedBox(height: 12),
                    // Issue #555: InlineError (live-region semantics), not a
                    // bare red Text.
                    InlineError(
                      key: const ValueKey('account-delete-export-error'),
                      message: exportError,
                      onRetry: _exporting ? null : _handleExport,
                    ),
                  ],
                ],
              ),
            ),
            actions: _buildActions(context, theme, blastRadius),
          );
        },
      ),
    );
  }

  /// The dialog's action row, split out of [build] to keep that method
  /// under the CRAP gate's complexity budget.
  List<Widget> _buildActions(
    BuildContext context,
    ThemeData theme,
    _DeleteAccountBlastRadius? blastRadius,
  ) => [
    TextButton(
      onPressed: _exporting
          ? null
          : () => Navigator.of(context).pop(DeleteAccountDecision.cancel),
      child: const Text('Cancel'),
    ),
    if (blastRadius != null && blastRadius.hasSharedOwnedProfile)
      TextButton(
        key: const ValueKey('account-delete-transfer-first'),
        onPressed: _exporting
            ? null
            : () => _handleTransferOwnership(blastRadius),
        child: const Text('Transfer ownership first'),
      ),
    TextButton(
      key: const ValueKey('account-delete-export-first'),
      onPressed: _exporting ? null : _handleExport,
      child: _exporting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Export first'),
    ),
    FilledButton(
      key: const ValueKey('account-delete-confirm'),
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.error,
        foregroundColor: theme.colorScheme.onError,
      ),
      // #17 P1 fix: guarded the same way as "Export first" above -
      // confirming delete while an export is reading the database
      // would let resetDevice() tear the database out from under
      // that in-flight read. #533: also gated on the blast radius
      // having loaded and, when it names a shared owned profile,
      // on the acknowledgement checkbox above.
      onPressed: _confirmEnabled(blastRadius)
          ? () => Navigator.of(context).pop(DeleteAccountDecision.delete)
          : null,
      child: const Text('Delete account'),
    ),
  ];
}

/// Shows [DeleteAccountDialog] and returns the operator's decision, or
/// `null` if it was dismissed some other way (treat like
/// [DeleteAccountDecision.cancel]).
Future<DeleteAccountDecision?> showDeleteAccountDialog(
  BuildContext context, {
  required Future<void> Function() onExport,
}) => showDialog<DeleteAccountDecision>(
  context: context,
  // #17 P1 fix: paired with the dialog's own PopScope(canPop: !
  // _exporting) - a barrier tap can't dismiss the dialog out from under
  // an in-flight export either.
  barrierDismissible: false,
  routeSettings: const RouteSettings(name: kRouteDeleteAccountDialog),
  builder: (_) => DeleteAccountDialog(onExport: onExport),
);
