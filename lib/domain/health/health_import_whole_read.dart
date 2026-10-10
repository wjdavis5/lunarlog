/// The device's memory that a health store's imported data was purged
/// (Issue #1876), so the next import pass reads the whole history.
///
/// "Remove imported data" tombstones the store's rows locally and clears
/// the memories that would hold a re-import back (the deletion memory and
/// the declined-record memory, beside this one) — the store is a clean
/// slate, and a later import is meant to bring everything it holds. But
/// the import reads from a stored position (an iPhone's `HKQueryAnchor`,
/// Health Connect's change token), and neither an anchored nor a changes
/// read returns a record that did not change since that position — so
/// after a purge the store's unchanged records were never offered to the
/// merge again, and the purged days stayed gone.
///
/// What is kept, per profile: one `app_settings` row saying a
/// whole-history read is owed. The import pass reads it, sends
/// `wholeHistory: true` on its first page (which drops the stored
/// position and reads everything), and clears it once a whole read
/// reached its end and its merge ran. It is set in the purge's own
/// transaction, so a crash before the next pass cannot lose the
/// obligation, and cleared with the profile's other health-import
/// memories when the profile is wiped from this device. Never synced: it
/// describes one phone's read position.
library;

/// What the health import reads and writes of that memory.
abstract interface class HealthImportWholeReadStore {
  /// Whether [profileId]'s next import pass must read the whole history.
  Future<bool> wholeReadOwed(String profileId);

  /// Remembers that it must. Called in the purge's own transaction, so a
  /// crash before the next pass cannot lose the obligation.
  Future<void> rememberWholeReadOwed(String profileId);

  /// Forgets it: a whole-history read reached its end and its merge ran,
  /// or the profile was wiped from this device.
  Future<void> forgetWholeReadOwed(String profileId);
}
