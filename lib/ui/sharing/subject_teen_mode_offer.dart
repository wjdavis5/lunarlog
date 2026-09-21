/// Issue #802: the one-time Teen-mode suggestion for a manager when a
/// minor subject joins her own profile.
///
/// * **Suggested, never forced** (#131's "mode is presentation, not
///   permission" constraint, restated by #802's non-goals): the dialog
///   offers the switch and declining writes nothing. The suggestion fires
///   at most once per profile — the latch is written before the dialog is
///   shown, so even a navigation-dismissed dialog never nags again.
/// * **Offered to a manager, not the subject**: care mode lives on the
///   profile (`profiles.mode`), and only a `primary_guardian`/`co_parent`
///   can edit profile metadata (server-enforced in `sync_push`) — the
///   caregiver-subject cannot switch it herself, so the offer surfaces in
///   Manage Guardians on a manager's device when the accepted subject row
///   first appears there.
/// * **Minor + Standard only**: an adult subject keeps `standard`
///   (#802's "leave `standard` for an adult subject"), and a profile
///   already in any other care mode (teen included) has nothing to
///   suggest. No age is computed from anything new — the existing
///   `Profile.isMinorAsOf` rule (birth year authoritative, stored flag
///   fallback) is the only input.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

/// Whether the Teen-mode suggestion applies: a minor subject has joined,
/// and the profile is still in Standard care mode. Pure — [now] is passed
/// in, never read here, so the condition is deterministic under test.
bool shouldOfferSubjectTeenMode(
  Profile profile, {
  required bool subjectJoined,
  required DateTime now,
}) =>
    subjectJoined &&
    profile.mode == ProfileMode.standard &&
    profile.isMinorAsOf(now);

/// Shows the suggestion and performs the write when accepted. Both seams
/// ([SettingsStore], [ProfileController]) are optional — a tree without
/// them simply never offers the dialog (the same null-gating discipline
/// as every other #802 surface), and a tree whose latch is already set
/// skips it too.
Future<void> offerSubjectTeenModeFromTree(
  BuildContext context, {
  required Profile profile,
}) async {
  final settings = _maybeRead<SettingsStore>(context);
  final controller = _maybeRead<ProfileController>(context);
  if (settings == null || controller == null) return;
  final latchKey = '${SettingsKeys.subjectTeenModeOffered}:${profile.id}';
  if (await settings.get(latchKey) != null) return;
  if (!context.mounted) return;
  // Latch before showing: the offer is once per profile, whatever the
  // answer (and however the dialog is dismissed).
  await settings.set(latchKey, 'shown');
  if (!context.mounted) return;
  final accepted = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: kRouteSubjectTeenModeDialog),
        builder: (dialogContext) {
          final l10n = AppLocalizations.of(dialogContext);
          return AlertDialog(
            title: Text(
              l10n.subjectTeenModeDialogTitle(profile.displayName),
              key: const ValueKey('subject-teen-mode-title'),
            ),
            content: SingleChildScrollView(
              child: Text(
                l10n.subjectTeenModeDialogBody(profile.displayName),
                key: const ValueKey('subject-teen-mode-body'),
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('subject-teen-mode-decline'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.subjectTeenModeDialogDecline),
              ),
              FilledButton(
                key: const ValueKey('subject-teen-mode-accept'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.subjectTeenModeDialogAccept),
              ),
            ],
          );
        },
      ) ??
      false;
  if (!accepted || !context.mounted) return;
  await controller.renameProfile(
    profile,
    displayName: profile.displayName,
    isMinor: profile.isMinor,
    mode: ProfileMode.teen,
    birthYear: profile.birthYear,
    relationship: profile.relationship,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AppLocalizations.of(context).subjectTeenModeDoneSnack,
        key: const ValueKey('subject-teen-mode-snack'),
      ),
    ),
  );
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T?>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
