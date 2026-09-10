/// Publishes one profile's prediction window to the server (Issue #5, U6;
/// KTD4, R13). The named domain contract that replaces the
/// `ReminderWindowUpsert` function typedef: the publisher speaks in this
/// interface, and the Supabase-backed implementation lives in
/// `lib/data/notifications/reminder_window_publisher.dart`'s composition
/// wiring.
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
}
