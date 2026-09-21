/// The undo half of the quick-log write (issues #856/#1016): restore exactly
/// what a "Period started today" tap overwrote.
///
/// Pure Dart (R14/R16). Extracted so the in-app today card
/// (`OverviewPanel._undoLogToday`) and the home-screen widget's outcome
/// handler (`lib/app.dart`) share one implementation — the Undo a widget
/// quick-log shows must reverse the write the same way the in-app one does,
/// not through a second, subtly different path.
library;

import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../repositories/day_entries_repository.dart';

/// Reverses a quick-log write through the repository's own save/delete
/// paths, so sync dirty-marking applies exactly as it would to any other
/// edit.
///
/// [previous] is the entry as it was *before* the write (the value a
/// logged outcome carries): when null the quick-log tap created the entry,
/// so undo tombstones it via [DayEntriesRepository.delete]; otherwise the
/// prior row is saved back, preserving whatever heavier flow, tags, or note
/// it held.
Future<void> undoQuickLogToday({
  required DayEntriesRepository dayEntries,
  required String profileId,
  required LocalDate date,
  required DayEntry? previous,
}) async {
  if (previous == null) {
    await dayEntries.delete(profileId, date);
  } else {
    await dayEntries.save(previous);
  }
}
