/// What the device remembers about health-store records she deleted in
/// lunarlog (Issue #1561), so that the next import does not bring them
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
/// It is written by the storage layer in the transaction that deletes the
/// row, for the two things she can do on this phone: delete a day, and
/// remove one entry from a day. Nothing else adds to it. In particular it
/// is NOT derived from deleted rows, and a deletion that arrives by sync is
/// not remembered: "Remove imported data" leaves deleted rows and sends
/// deletions to every device too, nothing in a row tells the two apart, and
/// after it an import must bring the days back.
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

/// The sources Apple Health's imports carry: days and the entries on them
/// have different ones.
const Set<String> _kAppleHealthSources = {'healthkit', 'apple_health'};

/// Every source that comes from the same health store as [source], itself
/// included; none when [source] is not a health store's (a file import).
/// Removing a store's imported data is a clean slate for the whole store,
/// whichever of its sources was named.
Set<String> healthStoreSourcesSharedWith(String source) {
  if (_kAppleHealthSources.contains(source)) return _kAppleHealthSources;
  if (kHealthStoreSources.contains(source)) return {source};
  return const {};
}

/// One remembered record's name: its source, then its record id.
String healthImportDeletionId(String source, String sourceId) =>
    '$source|$sourceId';
