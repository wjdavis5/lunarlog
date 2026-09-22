/// Repository contract for the upload-consent row counts (R14, AS4): how
/// many `profiles`/`day_entries` rows this device holds, tombstones
/// included, without the caller ever touching `LunarLogStorage` directly.
///
/// Issue #551 (part 3): the one seam `lib/app.dart` provides to the widget
/// tree for [LocalRowCounter], replacing its previous tear-off of
/// `widget.db.storage.countAllRows`. The read model ([LocalRowCounts]) and
/// the provider callback typedef ([LocalRowCounter]) already live in
/// `lib/domain/sync/local_row_counts.dart`; this interface is the
/// repository the composition module builds over the drift store.
library;

import '../sync/local_row_counts.dart';

abstract interface class LocalRowCountRepository {
  /// Row counts, live and tombstoned, of the two synced tables the
  /// upload-consent screen shows. Mirrors `LunarLogStorage.countAllRows`.
  Future<LocalRowCounts> countAllRows();
}
