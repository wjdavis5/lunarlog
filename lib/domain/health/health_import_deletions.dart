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
/// What is kept, per profile: the row's `sourceId` as the row held it (see
/// `_recordKey` in `health_import_service.dart`), under the row's source,
/// and the moment of the deletion. For a Health Connect record that names
/// the record and the time it was last changed; for one of a period
/// record's expanded days (Issue #1682) it also carries that day's date,
/// so deleting one day of the span is remembered for that day alone. No
/// flow, nothing else about the day. The record itself is still in the
/// health store on the same phone; this only says "not this one again".
///
/// A memory written before Issue #1682 for a day of a period span names
/// only the record and its time — the key every day of that span then
/// shared — so it cannot say which day she deleted. That day is imported
/// again once, and deleting it again records its own day key; nothing
/// migrates the old entry.
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
/// store the ids belong to. Two limits worth naming (Issue #1587 item 7):
/// a new phone, a reinstall, and a sign-out-and-back-in on the same phone
/// (the device reset deletes the database) each lose the memory, and a
/// deleted day — whose row is swept away shortly after it syncs — comes
/// back on the next import. There is no server-side copy, deliberately:
/// the ids name records in one phone's health store, which no other
/// device can read.
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
/// Removing a store's imported data clears the deletion memory for every
/// source whose rows go with it.
///
/// On an iPhone the days carry `healthkit` and the entries on them
/// `apple_health`: removing `healthkit` is a clean slate for the whole
/// store (the server cascades the entries on those days too, so both
/// sources' rows are gone), while removing `apple_health` — the
/// measurements, which touches no day — clears only its own memory
/// (Issue #1587 item 5: it used to clear `healthkit`'s too, so days she
/// deleted came back on the next import).
Set<String> healthStoreSourcesSharedWith(String source) {
  if (source == 'healthkit') return _kAppleHealthSources;
  if (kHealthStoreSources.contains(source)) return {source};
  return const {};
}

/// One remembered record's name: its source, then its record id.
String healthImportDeletionId(String source, String sourceId) =>
    '$source|$sourceId';
