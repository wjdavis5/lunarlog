/// Row counts of the two synced tables, tombstones included (deletions
/// upload too). Declared once here so `LunarLogStorage.countAllRows` and
/// the upload-consent screen share one shape without a drift type crossing
/// into `lib/ui`.
library;

typedef LocalRowCounts = ({int profiles, int dayEntries});

/// Supplies [LocalRowCounts]; the app provides `LunarLogStorage.countAllRows`.
typedef LocalRowCounter = Future<LocalRowCounts> Function();
