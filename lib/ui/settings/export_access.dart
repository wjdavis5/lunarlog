/// Resolves a profile's export access at the tile boundary (Issue #115,
/// gap G4): the viewer [GuardianLens] and whether the minor-profile guard
/// permits the export.
///
/// Every export tile (JSON, CSV, FHIR, PDF) resolves this once per chosen
/// profile from the same function, so the lens and the membership check are
/// never hand-rolled per format. The actual redaction is the pure
/// `redactForLens` in `lib/domain/export/export_redaction.dart`; this file
/// only supplies it the lens and the gate verdict from the widget tree.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/export/export_redaction.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/profile_guardian.dart';
import '../../domain/repositories/profile_guardians_repository.dart';
import '../../domain/sharing/guardian_lens.dart';
import '../account/auth_controller.dart';

/// The resolved export access for one profile.
class ExportAccess {
  const ExportAccess({required this.lens, required this.allowed});

  /// The lens the operator sees [profile] through; `redactForLens` uses it.
  final GuardianLens lens;

  /// Whether the minor-profile guard lets the operator export [profile].
  /// `false` means the tile must refuse with the "not available" copy and
  /// never call its export collaborator.
  final bool allowed;
}

/// Resolves [ExportAccess] from already-read membership facts — the pure
/// half, so a caller that must read several profiles' guardians before its
/// first `await` (the household JSON export) can reuse the same rule.
ExportAccess exportAccessFor({
  required Profile profile,
  required List<ProfileGuardian> guardians,
  required String? currentUserId,
  DateTime? today,
}) =>
    ExportAccess(
      lens: guardianLensFor(guardians, currentUserId),
      allowed: canExportMinorProfile(
        isMinor: profile.isMinorAsOf(today ?? DateTime.now()),
        guardians: guardians,
        currentUserId: currentUserId,
      ),
    );

/// Reads the operator's membership for [profile] from the tree and resolves
/// [ExportAccess].
///
/// A missing `ProfileGuardiansRepository` (an unconfigured build or a test
/// that provides none) and a missing `AuthController` both degrade to the
/// documented fail-open path: no membership facts, subject lens, minor
/// export allowed — the same nullable-provider discipline the rest of this
/// screen uses.
Future<ExportAccess> resolveExportAccess(
  BuildContext context,
  Profile profile, {
  DateTime? today,
}) async {
  final guardiansRepo = context.read<ProfileGuardiansRepository?>();
  final currentUserId =
      Provider.of<AuthController?>(context, listen: false)?.currentUserId;
  final guardians = guardiansRepo == null
      ? const <ProfileGuardian>[]
      : await guardiansRepo.getForProfile(profile.id);
  return exportAccessFor(
    profile: profile,
    guardians: guardians,
    currentUserId: currentUserId,
    today: today,
  );
}

/// [resolveExportAccess] with the refusal handled: returns the [ExportAccess]
/// when the export may proceed, or `null` after invoking [onRefused] when the
/// minor-profile guard refuses (or the widget unmounted while resolving).
///
/// Every export tile uses this one boundary so the "refuse and show the
/// not-available copy" branch lives in exactly one place, keeping each
/// tile's always-growing `_export` method inside the CRAP gate's complexity
/// budget.
Future<ExportAccess?> resolveExportAccessOrRefuse(
  BuildContext context,
  Profile profile,
  VoidCallback onRefused, {
  DateTime? today,
}) async {
  final access = await resolveExportAccess(context, profile, today: today);
  if (!context.mounted) return null;
  if (access.allowed) return access;
  onRefused();
  return null;
}
