/// What the device remembers about health-store records the import declined
/// (Issue #1652), so a later pass can ask the store for them again.
///
/// The merge decides each record against the day as it stands at that
/// moment, and two of its answers can change without the store changing: a
/// day with a flow she logged herself keeps its flow over the store's
/// record, and a spotting entry she logged keeps its place over an
/// intermenstrual-bleeding record. Since Issue #1646 an iPhone import reads
/// from a stored anchor, and an anchored read never returns a record that
/// did not change — so a record declined once was never offered again, and
/// clearing her own flow (or removing her own spotting entry) could no
/// longer let the store's value in.
///
/// What is kept, per profile: the store's record id under its source
/// (`<source>|<record id>`), the kind of record it was (a flow sample, or
/// an intermenstrual-bleeding record), and the civil date it resolved to.
/// No flow value, nothing about the day: the record is still in the health
/// store on this same phone, and the answer is always to read it again,
/// never to remember what it said.
///
/// A declined record is forgotten when the store reports it deleted, when
/// a later merge settles its date (the store's value was written, or the
/// day already carries it), when a finished whole-history read — owed
/// because her row changed — does not return it, and with the binding or a
/// purge of the store's imported data. Never synced: it lives in
/// `app_settings`, and the ids name records in one phone's health store.
library;

import 'package:lunarlog/domain/models/local_date.dart';

/// The kind of store record that was declined: a menstrual-flow sample
/// (merged into a day entry), or an intermenstrual-bleeding record
/// (merged into a spotting observation).
enum HealthImportDeclinedKind {
  flow,
  spotting;

  /// The short form kept in the settings value.
  String get wire => this == flow ? 'flow' : 'spotting';

  /// The kind [wire] names, or null for a value this build cannot read.
  static HealthImportDeclinedKind? fromWire(String wire) => switch (wire) {
    'flow' => flow,
    'spotting' => spotting,
    _ => null,
  };
}

/// One remembered declined record.
class HealthImportDeclinedRecord {
  const HealthImportDeclinedRecord({
    required this.key,
    required this.kind,
    required this.date,
  });

  /// `<source>|<record id>` — the same shape a remembered deletion uses,
  /// so the two memories read alike.
  final String key;

  /// Which merge declined it.
  final HealthImportDeclinedKind kind;

  /// The civil date the record resolved to.
  final LocalDate date;

  /// The record id [key] names, without its source.
  String get recordId => key.substring(key.indexOf('|') + 1);

  /// The source [key] names, without its record id.
  String get source => key.substring(0, key.indexOf('|'));
}

/// The name of one declined record's memory row: its source, then its
/// record id.
String healthImportDeclinedId(String source, String recordId) =>
    '$source|$recordId';

/// What the health import reads and writes of that memory.
abstract interface class HealthImportDeclinedStore {
  /// [profileId]'s remembered declined records, keyed by
  /// [HealthImportDeclinedRecord.key]. A value this build cannot read is
  /// skipped, the way a ledger row of an unknown kind is.
  Future<Map<String, HealthImportDeclinedRecord>> readDeclinedHealthRecords(
    String profileId,
  );

  /// Remembers [recordId] as declined for [date]. Remembering the same
  /// record again refreshes its date and kind.
  Future<void> rememberDeclinedHealthRecord(
    String profileId, {
    required String source,
    required String recordId,
    required HealthImportDeclinedKind kind,
    required LocalDate date,
  });

  /// Forgets the named records, keyed as [readDeclinedHealthRecords]
  /// returns them.
  Future<void> forgetDeclinedHealthRecords(
    String profileId,
    Set<String> keys,
  );
}
