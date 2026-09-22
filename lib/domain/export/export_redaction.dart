/// Per-viewer export redaction and the minor-profile export guard (Issue
/// #115, gap G4; issue #849). Pure Dart — no Flutter, no drift — so every
/// format builder's input can be funnelled through one function instead of
/// four copies drifting apart.
///
/// Two rules live here, both derived strictly from membership identity the
/// same way `guardian_lens.dart` derives the lens:
///
/// * **Guardian lens** ([redactForLens]): when the operator exporting is
///   not the profile's subject ([GuardianLens.guardian]), a day entry whose
///   [DayEntry.notePrivate] is set exports its [DayEntry.note] as `null` —
///   the text never leaves the device. This mirrors the server's
///   `mask_day_entry_note()` (issue #849), which forces `note` to `null`
///   for every non-subject accepted guardian of a profile that has a
///   designated subject. The subject lens ([GuardianLens.subject]) exports
///   in full, byte-identical to the pre-redaction output.
///
/// * **Minor-profile guard** ([canExportMinorProfile]): a profile flagged
///   as a minor's is exported only by an accepted guardian on that profile
///   (the subject holds an accepted membership too, so this covers "or is
///   the subject"). This is a presentation/UX gate backed by guardian
///   membership; the authoritative access-control fact remains RLS. It
///   fails open when there is no signed-in account or no membership rows
///   have synced yet — the documented `acceptedGuardianFor` posture every
///   other membership read in this codebase uses.
library;

import '../models/day_entry.dart';
import '../models/profile_guardian.dart';
import '../sharing/guardian_lens.dart';

/// Returns [entries] with every private day note stripped when [lens] is
/// [GuardianLens.guardian]; the subject lens returns the entries unchanged.
///
/// A "private" note is one the subject marked private ([DayEntry.notePrivate]
/// `true`). Its text is set to `null` while the flag itself is preserved —
/// exactly the shape the server's masking produces, so a reader can still
/// tell a private note was omitted rather than never written.
///
/// Applied to per-profile input *before* every format builder (JSON, CSV,
/// FHIR, PDF), never as a string filter over the encoded output: a new
/// format can only miss the rule by not calling this function, which a test
/// pins.
List<DayEntry> redactForLens(Iterable<DayEntry> entries, GuardianLens lens) {
  if (lens == GuardianLens.subject) return List<DayEntry>.of(entries);
  return [for (final entry in entries) _redactEntry(entry)];
}

DayEntry _redactEntry(DayEntry entry) {
  if (!entry.notePrivate || entry.note == null) return entry;
  return entry.copyWith(note: null);
}

/// Whether the current operator may export a profile flagged as a minor's
/// (Issue #115, G4; plan D-8).
///
/// `true` for any non-minor profile. For a minor profile it requires an
/// accepted membership for [currentUserId] among [guardians] — the subject
/// or any accepted guardian role both qualify, matching
/// [acceptedGuardianFor]'s identity-not-capability discipline. It fails
/// open (`true`) when [currentUserId] is null (a local-only operator) or
/// [guardians] is empty (membership rows have not synced yet), so a
/// signed-out device owner is never locked out of their own data. The bar
/// is deliberately "accepted guardian", not owner-only; a tighter role is
/// an owner decision recorded in the plan's open question OQ-2.
bool canExportMinorProfile({
  required bool isMinor,
  required List<ProfileGuardian> guardians,
  required String? currentUserId,
}) {
  if (!isMinor) return true;
  if (currentUserId == null || guardians.isEmpty) return true;
  return acceptedGuardianFor(guardians, currentUserId) != null;
}
