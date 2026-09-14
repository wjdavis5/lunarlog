/// Publishes one profile's prediction window to the server (Issue #5, U6;
/// KTD4, R13). The named domain contract that replaces the
/// `ReminderWindowUpsert` function typedef: the publisher speaks in this
/// interface, and the Supabase-backed implementation lives in
/// `lib/data/notifications/supabase_reminder_window_remote.dart`.
///
/// The contract is pure Dart — no Supabase type crosses it.
library;

abstract interface class ReminderWindowRemote {
  /// Publishes one profile's window. [estimatedNextStartIso] is the civil
  /// `yyyy-MM-dd` date the server's `date` column expects.
  Future<void> upsert({
    required String profileId,
    required String estimatedNextStartIso,
    required bool episodeOpen,
  });

  /// Deletes [profileId]'s published window, if any (issue LLA-061): a
  /// suppression transition (Pregnancy/Postpartum/Perimenopause, a
  /// continuous birth-control method, or predictions turned off) has no
  /// live estimate left to publish, so the *previous* one must stop
  /// being able to trigger `scan_missed_entry_reminders()` (its inner
  /// join on `profile_reminder_windows` would otherwise keep reading a
  /// stale row indefinitely). Idempotent: retracting an already-absent
  /// window is a no-op, not an error.
  Future<void> retract({required String profileId});
}
