/// What the device remembers about health-store records that were deleted
/// in lunarlog (Issue #1561), so that the next import does not bring them
/// back.
///
/// A deleted row keeps which record it was imported from, but only for as
/// long as the deleted row exists on the phone, and a clean deleted row is
/// swept two days after it has synced. The import then saw no trace of the
/// day and inserted it again. Keeping the deleted row longer is not an
/// option: deleted records are removed once they have synced. So the one
/// thing worth keeping is kept on its own.
///
/// What is kept, per profile: the store's record id as the row held it (see
/// `_recordKey` in `health_import_service.dart`), under the row's source,
/// and the moment of the deletion. No date, no flow, nothing about the day.
/// The record itself is still in the health store on the same phone; this
/// only says "not this one again".
///
/// It is written by the storage layer at the moment a row stops being
/// live, by any of the three ways that is a deletion of that row: she
/// deletes a day, she removes one entry from a day, or a deletion made on
/// another device arrives by sync. It is NOT derived from deleted rows:
/// "Remove imported data" also leaves deleted rows, and after that an
/// import must bring the days back.
///
/// Never synced: it lives in `app_settings`, and it is this phone's health
/// store the ids belong to.
library;

/// The row sources that mean "imported from this phone's health store": the
/// two day-entry sources and the two observation sources (Health Connect
/// uses one name for both).
const Set<String> kHealthStoreSources = {
  'healthkit',
  'health_connect',
  'apple_health',
};

/// One remembered record's name: its source, then its record id.
String healthImportDeletionId(String source, String sourceId) =>
    '$source|$sourceId';
