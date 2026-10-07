/// Issue #1594 end to end: a record deleted in the health store, over the
/// real repositories and a real database.
///
/// The import notes such a record and removes nothing. She is told, and
/// what was imported goes only when she asks. The removal then takes rows
/// out here, and the storage layer notes every row removed on this phone
/// as something she deleted (Issue #1561). Only a real database shows
/// whether the two agree: that what is taken out because the store
/// deleted it is not then held against the store.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart'
    show DayEntriesCompanion, LunarLogDatabase;
import 'package:lunarlog/data/health/health_import_service.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/health/health_import.dart';
import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/health/health_sync_binding.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';

const _profileId = 'p1';
const _ownerId = 'owner-user';

class _Platform implements HealthPlatformStore {
  @override
  bool writesCycleStart = true;

  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async =>
      const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> requestImportAuthorization(
    HealthGuardFacts facts,
  ) async =>
      const HealthPlatformAllowed();

  /// What a background pass asks before it reads.
  HealthPermissionStatus readAccess = HealthPermissionStatus.granted;

  @override
  Future<HealthPermissionStatus> importPermissionStatus() async => readAccess;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Health Connect, as far as the import can tell. It holds records, keeps
/// a position once a read has been committed, and from then on answers
/// with what was written and what was deleted since. Asked for the whole
/// history, it drops the position and answers with everything it holds.
class _Store implements HealthImportSource {
  final Map<String, HealthFlowSample> records = {};
  final List<String> _written = [];
  final List<String> _deleted = [];

  /// Whether a read has been committed: later reads are changes-only.
  bool hasPosition = false;

  /// Held open, no page is answered until it completes.
  Completer<void>? readGate;

  /// Every page request: whether it asked for the whole history.
  final List<bool> askedForWholeHistory = [];

  /// Every page request: its cursor, and whether it asked for the whole
  /// history.
  final List<(String?, bool)> requests = [];

  /// Changes pages to serve in order, in place of the one page that
  /// holds everything since the last commit.
  final List<HealthReadResult> changePages = [];

  /// When true a whole-history read comes one record to a page.
  bool wholeHistoryPaged = false;

  /// Pages a whole-history read asked for AGAIN serves in order, in place
  /// of the records: for a read that stops part-way.
  final List<HealthReadResult> wholeHistoryAgainPages = [];
  final List<String> commits = [];

  /// What a whole-history read answers, when not the records.
  HealthReadResult? wholeHistoryAnswer;

  /// Run when a whole-history read is asked for after the first import.
  Future<void> Function()? onWholeHistoryAgain;

  /// A store that names deleted records on a whole-history page, which the
  /// real one never does.
  List<String> deletedOnWholeHistoryPage = const [];

  void write(HealthFlowSample sample) {
    records[sample.recordId] = sample;
    _deleted.remove(sample.recordId);
    _written
      ..remove(sample.recordId)
      ..add(sample.recordId);
  }

  void delete(String recordId) {
    records.remove(recordId);
    _written.remove(recordId);
    _deleted.add(recordId);
  }

  @override
  Future<HealthReadResult> readMenstrualFlowPage(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
    required int pageSize,
    String? cursor,
    bool wholeHistory = false,
  }) async {
    askedForWholeHistory.add(wholeHistory);
    requests.add((cursor, wholeHistory));
    await readGate?.future;
    if (wholeHistory) {
      hasPosition = false;
      await onWholeHistoryAgain?.call();
    }
    if (hasPosition && changePages.isNotEmpty) return changePages.removeAt(0);
    if (wholeHistoryAgainPages.isNotEmpty && _readingAgain(wholeHistory)) {
      return wholeHistoryAgainPages.removeAt(0);
    }
    if (!hasPosition && wholeHistoryPaged) return _wholeHistoryPage(cursor);
    if (hasPosition) {
      return HealthReadResult.samples(
        [for (final id in _written) records[id]!],
        incremental: true,
        deletedRecordIds: [..._deleted],
        commitToken: 'changes',
      );
    }
    return wholeHistoryAnswer ??
        HealthReadResult.samples(
          records.values.toList(),
          deletedRecordIds: deletedOnWholeHistoryPage,
          commitToken: 'whole',
        );
  }

  bool _again = false;

  /// Whether this request belongs to a whole-history read that was asked
  /// for with a position stored.
  bool _readingAgain(bool wholeHistory) {
    if (wholeHistory) _again = true;
    return _again;
  }

  /// One record of a whole-history read; the cursor is the next index.
  HealthReadResult _wholeHistoryPage(String? cursor) {
    final all = records.values.toList();
    final index = cursor == null ? 0 : int.parse(cursor);
    final last = index >= all.length - 1;
    return HealthReadResult.samples(
      [if (index < all.length) all[index]],
      nextCursor: last ? null : '${index + 1}',
      commitToken: last ? 'whole' : null,
    );
  }

  @override
  Future<HealthPlatformResult> commitImport(
    HealthGuardFacts facts,
    String commitToken,
  ) async {
    commits.add(commitToken);
    hasPosition = true;
    _again = false;
    _written.clear();
    _deleted.clear();
    return const HealthPlatformResult.allowed();
  }

  @override
  Future<HealthDeviationReadResult> readCycleDeviations(
    HealthGuardFacts facts, {
    required DateTime start,
    required DateTime end,
  }) async =>
      const HealthDeviationReadResult.unavailable();

  @override
  Future<bool> pastDataSwitchOffered() async => true;

  @override
  Future<HealthPlatformResult> requestPastDataAccess(
    HealthGuardFacts facts,
  ) async =>
      const HealthPlatformResult.allowed();
}

/// The real repository, with something run just before the next lookup of
/// a day: for a row that changes in the middle of a removal.
class _HookedDays implements DayEntriesRepository, DeletedDayEntryReader {
  _HookedDays(this._inner);

  final DriftDayEntriesRepository _inner;
  Future<void> Function()? beforeNextFind;

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async {
    final hook = beforeNextFind;
    beforeNextFind = null;
    await hook?.call();
    return _inner.find(profileId, localDate);
  }

  @override
  Future<List<DayEntry>> listForProfile(String profileId) =>
      _inner.listForProfile(profileId);

  @override
  Future<DayEntry> save(DayEntry entry) => _inner.save(entry);

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);

  @override
  Future<Map<String, DateTime>> deletedHealthRecords(String profileId) =>
      _inner.deletedHealthRecords(profileId);

  @override
  Future<void> forgetDeletedHealthRecords(
    String profileId,
    Map<String, DateTime> deletedAt,
  ) =>
      _inner.forgetDeletedHealthRecords(profileId, deletedAt);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A flow record on September [day] 2026, local midnight at UTC-4, last
/// changed at [modifiedAt] when its store changes a record in place (Health
/// Connect); null where a sample cannot be edited (Apple Health), so the
/// record id is the row's whole key.
HealthFlowSample _flow(
  String id,
  int day,
  HealthFlowValue flow, {
  DateTime? modifiedAt,
}) {
  final start = DateTime.utc(2026, 9, day, 4);
  return HealthFlowSample(
    recordId: id,
    flow: flow,
    start: start,
    end: start.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
    offset: const Duration(hours: -4),
    modifiedAt: modifiedAt,
  );
}

HealthFlowSample _spotting(String id, int day) {
  final start = DateTime.utc(2026, 9, day, 16);
  return HealthFlowSample(
    recordId: id,
    kind: HealthSampleKind.intermenstrualBleeding,
    start: start,
    end: start,
    offset: const Duration(hours: -4),
  );
}

/// The `day_entries.source` rows imported from [platform] carry — mirrors
/// `LocalHealthImportService`'s private getter (Issue #1610: the deletion
/// rules hold on both stores, so the suite runs once per platform).
DayEntrySource _daySourceOf(HealthImportPlatform platform) =>
    platform == HealthImportPlatform.healthConnect
        ? DayEntrySource.healthConnect
        : DayEntrySource.healthkit;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  for (final platform in HealthImportPlatform.values) {
    runSuite(platform);
  }
}

/// The whole deletion suite over [platform]: the same rules on Health
/// Connect and on Apple Health. The two stores differ in two ways the
/// suite shapes itself around — the provenance stamped on imported rows,
/// and whether a record can be changed in place (an Apple Health sample
/// carries no last-changed time, so its id is the row's whole key).
void runSuite(HealthImportPlatform platform) {
  late LunarLogDatabase db;
  late DriftDayEntriesRepository days;
  late DriftObservationsRepository observations;
  late HealthSyncBinding binding;
  late DriftProfilesRepository profiles;
  late _Store store;
  late LocalHealthImportService import;

  LocalDate sept(int day) => LocalDate(2026, 9, day);

  /// A flow record on September [day] 2026, shaped for [platform]:
  /// [modifiedHour] names when Health Connect last changed the record, and
  /// an Apple Health sample carries no such time.
  HealthFlowSample flow(
    String id,
    int day,
    HealthFlowValue value, {
    int modifiedHour = 12,
  }) =>
      _flow(
        id,
        day,
        value,
        modifiedAt: platform == HealthImportPlatform.healthConnect
            ? DateTime.utc(2026, 9, day, modifiedHour)
            : null,
      );

  /// The import service over the test's database, reading and writing
  /// days through [dayEntries].
  LocalHealthImportService serviceOver(DayEntriesRepository dayEntries) =>
      LocalHealthImportService(
        importPlatform: platform,
        platform: _Platform(),
        source: store,
        binding: binding,
        minorBindingAllowed: false,
        profiles: profiles,
        dayEntries: dayEntries,
        observations: observations,
        guardiansForProfile: (_) async => [
          ProfileGuardian(
            id: 'g1',
            profileId: _profileId,
            userId: _ownerId,
            role: GuardianRole.primaryGuardian,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        signedInUserId: () => _ownerId,
        today: () => LocalDate(2026, 9, 30),
      );

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    days = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
    profiles = DriftProfilesRepository(db.storage);
    await db.storage.upsertProfile(
      id: _profileId,
      displayName: 'Ada',
      isMinor: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    binding = HealthSyncBinding(DriftSettingsStore(db.storage));
    await binding.bind(
      profile: (await profiles.findById(_profileId))!,
      signedInUserId: _ownerId,
      ownerUserId: _ownerId,
      minorBindingAllowed: false,
    );
    store = _Store();
    import = serviceOver(days);
  });

  Future<DayEntry?> dayOn(int day) => days.find(_profileId, sept(day));

  Future<List<Observation>> entriesOn(int day) async {
    final row = await dayOn(day);
    if (row == null) return const [];
    return observations.listForDayEntry(row.id);
  }

  /// The first import of [samples]: a whole-history read, after which the
  /// store answers with changes only.
  Future<void> imported(List<HealthFlowSample> samples) async {
    samples.forEach(store.write);
    await import.importNow();
    expect(store.hasPosition, isTrue);
    store.askedForWholeHistory.clear();
    store.requests.clear();
    store.commits.clear();
  }

  /// The records are deleted in the store, and an import notes it.
  Future<HealthImportSummary> deletedInStore(List<String> recordIds) {
    recordIds.forEach(store.delete);
    return import.importNow();
  }

  /// How many days are on offer.
  Future<int> onOffer() async => (await import.daysDeletedInStore()).days;

  /// She is shown the offer as it stands, and says Remove.
  Future<HealthImportSummary> removeOffered([
    LocalHealthImportService? through,
  ]) async =>
      (through ?? import)
          .removeDaysDeletedInStore(await import.daysDeletedInStore());

  /// She is shown the offer as it stands, and says Keep.
  Future<void> keepOffered() async =>
      import.keepDaysDeletedInStore(await import.daysDeletedInStore());

  group('an import that finds a record was deleted', () {
    test('removes nothing: the day stays, and is offered', () async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
      ]);

      final summary = await deletedInStore(['rec-10']);

      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(summary.daysRemoved, 0);
      expect(summary.isEmpty, isTrue,
          reason: 'the pass read no sample and changed no day');
      expect(await onOffer(), 1);
      // An ordinary changes read, committed as one.
      expect(store.requests, [(null, false)]);
      expect(store.commits, ['changes']);
    });

    test('the store says so once; the days stay on offer over later imports '
        'and a new service', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);

      await import.importNow();
      await import.importNow();

      expect(await onOffer(), 1);
      expect(await binding.storeDeletedRecordIds(), {'rec-10'});
    });

    test('a background pass notes them too, and removes nothing', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      store.delete('rec-10');

      await import.importInBackground();

      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(await onOffer(), 1);
    });

    test('only the records a row here was imported from are kept on the '
        'list', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);

      await deletedInStore(['rec-10', 'one-of-lunarlogs-own-writes']);

      expect(await binding.storeDeletedRecordIds(), {'rec-10'});
    });

    test('a deleted record nothing was imported from is not offered, and '
        'nothing is stored', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);

      await deletedInStore(['one-of-lunarlogs-own-writes']);

      expect(await onOffer(), 0);
      expect(await binding.storeDeletedRecordIds(), isEmpty);
    });

    // An app that edits by deleting a record and writing a new one.
    test('a day whose record was replaced takes the new one, and is not '
        'offered', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      store
        ..delete('rec-10')
        ..write(flow('rec-10b', 10, HealthFlowValue.light));

      final summary = await import.importNow();

      final day = (await dayOn(10))!;
      expect(day.flow, FlowLevel.light);
      if (platform == HealthImportPlatform.healthConnect) {
        expect(day.sourceId, startsWith('rec-10b@'));
      } else {
        expect(day.sourceId, 'rec-10b',
            reason: 'a HealthKit sample cannot be edited, '
                'so the id is the row\'s whole key');
      }
      expect(summary.daysWritten, 1);
      expect(await onOffer(), 0);
      expect(await binding.storeDeletedRecordIds(), isEmpty);
    });

    test('a spotting entry whose record was replaced takes the new one, and is '
        'not offered (#1621)', () async {
      await imported([_spotting('spot-11', 11)]);
      store
        ..delete('spot-11')
        ..write(_spotting('spot-11b', 11));

      await import.importNow();

      expect(
        (await entriesOn(11)).map((entry) => entry.sourceId),
        ['spot-11b'],
      );
      expect(await onOffer(), 0);
      expect(await binding.storeDeletedRecordIds(), isEmpty);
    });

    test('a record that comes back under the same id is no longer offered',
        () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);
      expect(await onOffer(), 1);

      store.write(flow('rec-10', 10, HealthFlowValue.medium, modifiedHour: 18));
      await import.importNow();

      expect(await onOffer(), 0);
      if (platform == HealthImportPlatform.healthConnect) {
        expect((await dayOn(10))!.flow, FlowLevel.medium);
      } else {
        // An Apple Health sample cannot change: the same id back means the
        // same sample, and the day keeps the value it was imported with.
        expect((await dayOn(10))!.flow, FlowLevel.heavy);
      }
    });

    test('a day she deletes herself meanwhile is no longer offered',
        () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);

      await days.delete(_profileId, sept(10));

      expect(await onOffer(), 0);
    });

    test('a spotting entry and a flow on the same day are one day',
        () async {
      await imported([
        flow('rec-11', 11, HealthFlowValue.light),
        _spotting('spot-11', 11),
      ]);

      await deletedInStore(['rec-11', 'spot-11']);

      expect(await onOffer(), 1);
    });

    test('Keep clears the offer and leaves the days', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);

      await keepOffered();

      expect(await onOffer(), 0);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      await import.importNow();
      expect(await onOffer(), 0);
    });

    test('choosing a profile again, or stopping the sync, clears the offer',
        () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);

      await binding.unbind();
      expect(await binding.storeDeletedRecordIds(), isEmpty);
      expect(await onOffer(), 0);
    });

    test('a record a whole-history read does not return is not a deleted '
        'record', () async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      // Hidden, as with "Access past data" off: gone from what a read
      // returns, and no deletion reported.
      store.records.remove('rec-10');
      store.hasPosition = false;

      await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(await onOffer(), 0);
    });

    test('only a changes page can say a record was deleted', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      store
        ..hasPosition = false
        ..deletedOnWholeHistoryPage = const ['rec-10'];

      await import.importNow();

      expect(await onOffer(), 0);
    });

    // Pages come in the order things happened.
    test('a record deleted on one page and written again on a later one is '
        'in the store: its day takes the new value and is not offered',
        () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      store.changePages.addAll([
        HealthReadResult.samples(
          const [],
          incremental: true,
          deletedRecordIds: const ['rec-10'],
          nextCursor: 'page-2',
        ),
        HealthReadResult.samples(
          [flow('rec-10', 10, HealthFlowValue.medium, modifiedHour: 18)],
          incremental: true,
          commitToken: 'changes',
        ),
      ]);

      await import.importNow();

      expect(await onOffer(), 0);
      if (platform == HealthImportPlatform.healthConnect) {
        expect((await dayOn(10))!.flow, FlowLevel.medium);
      } else {
        // An Apple Health sample cannot change, so "written again" is the
        // same sample: the ordering still clears the offer, and the day
        // keeps the value it was imported with.
        expect((await dayOn(10))!.flow, FlowLevel.heavy);
      }
      expect(store.requests, [(null, false), ('page-2', false)]);
    });

    // Its sample has been taken for the day's value by the time the
    // deletion is read, so what was gathered cannot be used.
    test('a record written on one page and deleted on a later one is not '
        'imported: everything is read again', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      store.changePages.addAll([
        HealthReadResult.samples(
          [flow('rec-20', 20, HealthFlowValue.medium)],
          incremental: true,
          nextCursor: 'page-2',
        ),
        HealthReadResult.samples(
          const [],
          incremental: true,
          deletedRecordIds: const ['rec-20'],
          commitToken: 'changes',
        ),
      ]);

      final summary = await import.importNow();

      expect(await dayOn(20), isNull);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(summary.daysRemoved, 0);
      expect(store.requests, [(null, false), ('page-2', false), (null, true)]);
      expect(store.commits, ['whole']);
    });

    // That second read is the one a removal makes. Made by an import, it
    // must not take the removal with it.
    test('reading everything again for that removes nothing that is on '
        'offer', () async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      await deletedInStore(['rec-11']);
      expect(await onOffer(), 1);
      store.changePages.addAll([
        HealthReadResult.samples(
          [flow('rec-20', 20, HealthFlowValue.medium)],
          incremental: true,
          nextCursor: 'page-2',
        ),
        HealthReadResult.samples(
          const [],
          incremental: true,
          deletedRecordIds: const ['rec-20'],
          commitToken: 'changes',
        ),
      ]);

      final summary = await import.importNow();

      expect(store.askedForWholeHistory.last, isTrue);
      expect(summary.daysRemoved, 0);
      expect((await dayOn(11))!.flow, FlowLevel.medium);
      expect(await onOffer(), 1);
    });
  });

  group('removing the days, when she asks', () {
    test('takes the day out, after everything has been read again',
        () async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      await deletedInStore(['rec-10']);
      store.requests.clear();
      store.commits.clear();

      final summary = await removeOffered();

      expect(await dayOn(10), isNull);
      expect((await dayOn(11))!.flow, FlowLevel.medium);
      expect(summary.daysRemoved, 1);
      expect(summary.isEmpty, isFalse);
      // Before anything else reads the list: the removal cleared it.
      expect(await binding.storeDeletedRecordIds(), isEmpty);
      expect(await onOffer(), 0);
      // What changed since the last pass first, so that a deletion in that
      // stretch is not lost with the position; then everything.
      expect(store.requests, [(null, false), (null, true)]);
      expect(store.commits, ['whole']);
    });

    test('with nothing on offer it is an import that reads everything, and '
        'removes nothing', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);

      final summary = await removeOffered();

      expect(summary.daysRemoved, 0);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
    });

    test('is not remembered as a day she deleted, so the same record is '
        'imported if the store offers it again', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);
      await removeOffered();
      expect(await dayOn(10), isNull);
      expect(await days.deletedHealthRecords(_profileId), isEmpty);

      // The same record, unchanged: a remembered deletion would keep it out.
      store.write(flow('rec-10', 10, HealthFlowValue.heavy));
      await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.heavy);
    });

    test('a day she deleted herself is still remembered afterwards',
        () async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      await days.delete(_profileId, sept(11));
      final hers = await days.deletedHealthRecords(_profileId);
      expect(hers, hasLength(1));
      await deletedInStore(['rec-10']);

      await removeOffered();

      expect(await days.deletedHealthRecords(_profileId), hers);
      expect(await dayOn(11), isNull, reason: 'and her deletion still holds');
    });

    test('leaves the day when it carries a tag of hers, and takes only the '
        'flow', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save((await dayOn(10))!.copyWith(tags: const ['cramps']));
      await deletedInStore(['rec-10']);

      final summary = await removeOffered();

      final day = (await dayOn(10))!;
      expect(day.flow, FlowLevel.none);
      expect(day.tags, ['cramps']);
      expect(day.sourceId, isNull, reason: 'it names no record any more');
      expect(summary.daysRemoved, 1);
      expect(await days.deletedHealthRecords(_profileId), isEmpty);
    });

    for (final (what, change) in <(String, DayEntry Function(DayEntry))>[
      ('a note', (day) => day.copyWith(note: 'felt fine')),
      ('the PMS mark', (day) => day.copyWith(pms: true)),
      // The person the profile is about wrote one on her own account. This
      // phone cannot see it, and deleting the row would delete it.
      ('a private note it cannot see', (day) => day.copyWith(notePrivate: true)),
    ]) {
      test('leaves the day when it carries $what', () async {
        await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
        await days.save(change((await dayOn(10))!));
        await deletedInStore(['rec-10']);

        await removeOffered();

        expect((await dayOn(10))!.flow, FlowLevel.none);
      });
    }

    test('leaves the day when it carries an entry of hers', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      final day = (await dayOn(10))!;
      await observations.save(
        Observation(
          id: '',
          dayEntryId: day.id,
          profileId: _profileId,
          localDate: day.localDate,
          tz: day.tz,
          category: ObservationCategory.pain,
          code: 'cramps',
          intensity: 3,
          updatedAt: DateTime.utc(2026, 9, 10, 13),
        ),
      );
      await deletedInStore(['rec-10']);

      await removeOffered();

      expect((await dayOn(10))!.flow, FlowLevel.none);
      expect(await entriesOn(10), hasLength(1));
    });

    test('a day left with no flow takes one from the store again', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save((await dayOn(10))!.copyWith(tags: const ['cramps']));
      await deletedInStore(['rec-10']);
      await removeOffered();

      store.write(flow('rec-10b', 10, HealthFlowValue.light));
      await import.importNow();

      final day = (await dayOn(10))!;
      expect(day.flow, FlowLevel.light);
      expect(day.tags, ['cramps']);
    });

    // The reason for the whole-history read: a changes-only read never
    // returns a record that did not change.
    test('when the store holds another record for the day, the day takes '
        'that one\'s value', () async {
      await imported([
        flow('rec-heavy', 10, HealthFlowValue.heavy),
        flow('rec-light', 10, HealthFlowValue.light),
      ]);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      await deletedInStore(['rec-heavy']);

      final summary = await removeOffered();

      expect((await dayOn(10))!.flow, FlowLevel.light);
      expect(summary.daysRemoved, 1);
      expect(summary.daysWritten, 1);
    });

    test('a day she corrected after importing it goes too: it still names '
        'the record', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save((await dayOn(10))!.copyWith(flow: FlowLevel.light));
      await deletedInStore(['rec-10']);
      expect(await onOffer(), 1);

      await removeOffered();

      expect(await dayOn(10), isNull);
    });

    test('a day she logged herself is never touched', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save(
        DayEntry(
          id: '',
          profileId: _profileId,
          localDate: sept(12),
          tz: 'America/New_York',
          flow: FlowLevel.medium,
          updatedAt: DateTime.utc(2026, 9, 12, 13),
        ),
      );
      await deletedInStore(['rec-10']);

      await removeOffered();

      expect((await dayOn(12))!.flow, FlowLevel.medium);
    });

    // A day imported by a build from before #1559 names its record by the
    // id alone, with no time after it.
    test('a day an earlier build imported, which names its record by the id '
        'alone, is found and goes', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save((await dayOn(10))!.copyWith(sourceId: 'rec-10'));
      await deletedInStore(['rec-10']);
      expect(await onOffer(), 1);

      await removeOffered();

      expect(await dayOn(10), isNull);
      expect(await days.deletedHealthRecords(_profileId), isEmpty);
    });

    // The time comes after the LAST @ of a row's key.
    // A Health Connect row's key carries the time after the LAST @ of the
    // record id. An Apple Health sample UUID never carries an @, so there
    // is nothing for the strip to do there: the rule is Health Connect's.
    if (platform == HealthImportPlatform.healthConnect) {
      test('a record id with an @ in it is matched whole', () async {
        await imported([flow('rec@10', 10, HealthFlowValue.heavy)]);

        await deletedInStore(['rec']);
        expect(await onOffer(), 0);

        await deletedInStore(['rec@10']);
        expect(await onOffer(), 1);
        await removeOffered();
        expect(await dayOn(10), isNull);
      });
    }

    // Deleting a day takes every entry on its date with it, whichever row
    // the entry hangs on. So the day is looked at by date.
    test('leaves the day when an entry of hers for that date hangs on '
        'another row', () async {
      // A deleted row for the date arrives by sync without the deletion
      // of the entry on it: the entry is live, on a row that is not.
      final earlier = await days.save(
        DayEntry(
          id: '',
          profileId: _profileId,
          localDate: sept(10),
          tz: 'America/New_York',
          flow: FlowLevel.none,
          updatedAt: DateTime.utc(2026, 9, 10, 13),
        ),
      );
      await observations.save(
        Observation(
          id: '',
          dayEntryId: earlier.id,
          profileId: _profileId,
          localDate: sept(10),
          tz: earlier.tz,
          category: ObservationCategory.pain,
          code: 'cramps',
          intensity: 3,
          updatedAt: DateTime.utc(2026, 9, 10, 13),
        ),
      );
      await (db.update(db.dayEntries)
            ..where((row) => row.id.equals(earlier.id)))
          .write(
        DayEntriesCompanion(deletedAt: Value(DateTime.utc(2026, 9, 10, 14))),
      );
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      final day = (await dayOn(10))!;
      expect(day.id, isNot(earlier.id));
      expect(await entriesOn(10), isEmpty, reason: 'not on the live row');
      await deletedInStore(['rec-10']);

      await removeOffered();

      expect((await dayOn(10))!.flow, FlowLevel.none);
      expect(
        [
          for (final entry in await observations.listForProfile(_profileId))
            entry.code,
        ],
        ['cramps'],
      );
    });

    // The same id under another source is another record: a file import's
    // row, or one from another kind of store.
    test('a day from another source that carries the same id is not this '
        'store\'s: it is not offered and not touched', () async {
      await imported([flow('rec-11', 11, HealthFlowValue.medium)]);
      await days.save(
        DayEntry(
          id: '',
          profileId: _profileId,
          localDate: sept(12),
          tz: 'America/New_York',
          flow: FlowLevel.heavy,
          source: DayEntrySource.fileImport,
          sourceId: 'rec-12',
          updatedAt: DateTime.utc(2026, 9, 12, 13),
        ),
      );

      await deletedInStore(['rec-12']);

      expect(await onOffer(), 0);
      await removeOffered();
      expect((await dayOn(12))!.flow, FlowLevel.heavy);
    });

    test('as many days as the store deleted, when she asks', () async {
      const count = 12;
      await imported([
        for (var day = 1; day <= count; day++)
          flow('rec-$day', day, HealthFlowValue.medium),
      ]);
      await deletedInStore([for (var day = 1; day <= count; day++) 'rec-$day']);
      expect(await onOffer(), count);
      expect(await days.listForProfile(_profileId), hasLength(count),
          reason: 'none removed until she asks');

      final summary = await removeOffered();

      expect(summary.daysRemoved, count);
      expect(await days.listForProfile(_profileId), isEmpty);
    });

    // The whole history is read between finding the row and removing it.
    test('a day whose row names another record by the time it is to be '
        'removed is left as it is', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);
      final row = (await dayOn(10))!;
      store.onWholeHistoryAgain = () async {
        await days.save(row.copyWith(sourceId: 'rec-other@1'));
      };

      final summary = await removeOffered();

      final day = (await dayOn(10))!;
      expect(day.flow, FlowLevel.heavy);
      expect(day.sourceId, 'rec-other@1');
      expect(summary.daysRemoved, 0);
    });

    // After the list of days to remove has been made, and before this
    // day's turn: the narrowest place a save can land.
    test('a day that takes another record in the middle of the removal is '
        'left as it is, and is not counted', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);
      final hooked = _HookedDays(days)
        ..beforeNextFind = () async {
          await days.save(
            (await dayOn(10))!.copyWith(
              flow: FlowLevel.light,
              sourceId: 'rec-other@5',
            ),
          );
        };

      final summary = await removeOffered(serviceOver(hooked));

      expect(hooked.beforeNextFind, isNull, reason: 'the save landed');
      final day = (await dayOn(10))!;
      expect(day.flow, FlowLevel.light);
      expect(day.sourceId, 'rec-other@5');
      expect(summary.daysRemoved, 0);
    });

    // A long removal reads the entries once, before the first day. One
    // that lands on a day after that lands on the day's live row.
    test('an entry that lands on a day in the middle of the removal is not '
        'deleted with it: the day stays, without the flow', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);
      final hooked = _HookedDays(days)
        ..beforeNextFind = () async {
          final day = (await dayOn(10))!;
          await observations.save(
            Observation(
              id: '',
              dayEntryId: day.id,
              profileId: _profileId,
              localDate: day.localDate,
              tz: day.tz,
              category: ObservationCategory.pain,
              code: 'cramps',
              intensity: 3,
              updatedAt: DateTime.utc(2026, 9, 10, 13),
            ),
          );
        };

      final summary = await removeOffered(serviceOver(hooked));

      expect(hooked.beforeNextFind, isNull, reason: 'the entry landed');
      expect((await dayOn(10))!.flow, FlowLevel.none);
      expect((await entriesOn(10)).map((entry) => entry.code), ['cramps']);
      expect(summary.daysRemoved, 1);
    });

    test('a day she deletes herself while the store is being read again is '
        'hers: it is not counted, and stays remembered', () async {
      await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
      await deletedInStore(['rec-10']);
      store.onWholeHistoryAgain = () => days.delete(_profileId, sept(10));

      final summary = await removeOffered();

      expect(summary.daysRemoved, 0);
      expect(await days.deletedHealthRecords(_profileId), hasLength(1));
    });

    // Asking again on a later page would start the read over each time.
    test('only the first page of the second read asks for the whole history',
        () async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
        flow('rec-12', 12, HealthFlowValue.light),
      ]);
      await deletedInStore(['rec-10']);
      store
        ..requests.clear()
        ..wholeHistoryPaged = true;

      final summary = await removeOffered();

      expect(store.requests, [
        (null, false),
        (null, true),
        ('1', false),
      ]);
      expect(summary.daysRemoved, 1);
      expect(summary.pagesRead, 2);
      expect((await dayOn(11))!.flow, FlowLevel.medium);
      expect((await dayOn(12))!.flow, FlowLevel.light);
    });
  });

  // The second review of #1609. The offer she is shown names records,
  // and both answers are about those records and no others.
  group('she answers about what she was shown', () {
    Future<HealthStoreDeletedOffer> shownOneDay() async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      await deletedInStore(['rec-10']);
      final offer = await import.daysDeletedInStore();
      expect(offer.days, 1);
      expect(offer.recordIds, {'rec-10'});
      return offer;
    }

    // She clears the other app out after reading "1 day", and taps
    // Remove before any import has run. The removal's own read is the
    // first to hear of it.
    test('a record deleted after she was asked is not removed with the '
        'rest, and is offered next', () async {
      final offer = await shownOneDay();
      store.delete('rec-11');

      final summary = await import.removeDaysDeletedInStore(offer);

      expect(summary.daysRemoved, 1);
      expect(await dayOn(10), isNull);
      expect((await dayOn(11))!.flow, FlowLevel.medium);
      expect(await binding.storeDeletedRecordIds(), {'rec-11'});
      expect(await onOffer(), 1);
    });

    test('nor is one a background pass noted while the offer was on the '
        'screen', () async {
      final offer = await shownOneDay();
      store.delete('rec-11');
      await import.importInBackground();
      expect(await binding.storeDeletedRecordIds(), {'rec-10', 'rec-11'});

      final summary = await import.removeDaysDeletedInStore(offer);

      expect(summary.daysRemoved, 1);
      expect(await dayOn(10), isNull);
      expect((await dayOn(11))!.flow, FlowLevel.medium);
      expect(await onOffer(), 1);
    });

    test('Keep answers only what she was shown', () async {
      final offer = await shownOneDay();
      store.delete('rec-11');
      await import.importInBackground();

      await import.keepDaysDeletedInStore(offer);

      expect(await binding.storeDeletedRecordIds(), {'rec-11'});
      expect(await onOffer(), 1);
    });

    // The list is what the store has said. An offer read earlier only
    // says which of it she was asked about.
    test('an offer she already answered with Keep removes nothing',
        () async {
      final offer = await shownOneDay();
      await import.keepDaysDeletedInStore(offer);

      final summary = await import.removeDaysDeletedInStore(offer);

      expect(summary.daysRemoved, 0);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
    });

    test('a record that is back in the store by the time she says Remove '
        'is not removed', () async {
      final offer = await shownOneDay();
      store.write(flow('rec-10', 10, HealthFlowValue.heavy));

      final summary = await import.removeDaysDeletedInStore(offer);

      expect(summary.daysRemoved, 0);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(await binding.storeDeletedRecordIds(), isEmpty);
    });

    // The read of everything finds it, though no changes read said so.
    test('nor one that only the read of everything finds in the store',
        () async {
      final offer = await shownOneDay();
      store.onWholeHistoryAgain = () async {
        store.records['rec-10'] = flow('rec-10', 10, HealthFlowValue.heavy);
      };

      final summary = await import.removeDaysDeletedInStore(offer);

      expect(summary.daysRemoved, 0);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(await binding.storeDeletedRecordIds(), isEmpty);
    });

    // Asking must not write: a write from the screen could land between
    // a pass's read of the list and its write.
    test('asking what is on offer writes nothing', () async {
      await shownOneDay();
      await binding.setStoreDeletedRecordIds({'rec-10', 'no-row-names-me'});

      final offer = await import.daysDeletedInStore();

      expect(offer.days, 1);
      expect(offer.recordIds, {'rec-10'});
      expect(
        await binding.storeDeletedRecordIds(),
        {'rec-10', 'no-row-names-me'},
      );
    });

    test('Keep waits for a pass that is running, so the pass cannot put '
        'back what she answered', () async {
      final offer = await shownOneDay();
      store.readGate = Completer<void>();
      final pass = import.importNow();
      await pumpEventQueue();

      final kept = import.keepDaysDeletedInStore(offer);
      await pumpEventQueue();
      expect(await binding.storeDeletedRecordIds(), {'rec-10'},
          reason: 'not yet: the pass has the list in hand');

      store.readGate!.complete();
      await pass;
      await kept;
      expect(await binding.storeDeletedRecordIds(), isEmpty);
    });

    test('with no profile bound nothing is on offer', () async {
      await shownOneDay();
      await binding.unbind();

      final offer = await import.daysDeletedInStore();

      expect(offer.isEmpty, isTrue);
      expect(offer.recordIds, isEmpty);
    });
  });

  group('a removal whose read of everything does not finish', () {
    Future<void> offered() async {
      await imported([
        flow('rec-10', 10, HealthFlowValue.heavy),
        flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      await deletedInStore(['rec-10']);
      store.commits.clear();
    }

    Future<void> expectNothingRemoved(HealthImportSummary summary) async {
      expect(summary.isBlocked, isTrue);
      expect(summary.daysRemoved, 0);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(await onOffer(), 1,
          reason: 'the day is still on offer');
      expect(store.commits, isEmpty);
    }

    test('that cannot start: nothing is removed, and the day stays on offer',
        () async {
      await offered();
      store.wholeHistoryAgainPages
          .add(const HealthReadResult.unavailable());

      final summary = await removeOffered();

      await expectNothingRemoved(summary);
      expect(summary.blocked, isA<HealthPlatformUnavailable>(),
          reason: 'what stopped it is what is reported');
    });

    test('that fails on a later page', () async {
      await offered();
      store.wholeHistoryAgainPages.addAll([
        HealthReadResult.samples(
          [flow('rec-11', 11, HealthFlowValue.medium)],
          nextCursor: 'page-2',
        ),
        const HealthReadResult.failed('the store went away'),
      ]);

      final summary = await removeOffered();

      await expectNothingRemoved(summary);
      expect(
        summary.blocked,
        isA<HealthPlatformFailed>()
            .having((failed) => failed.message, 'message', 'the store went away'),
      );
    });

    // An import treats a page the store would not let be read as "no
    // data". A removal must not: the read did not reach its end.
    test('whose later page the store will not let be read', () async {
      await offered();
      store.wholeHistoryAgainPages.addAll([
        HealthReadResult.samples(
          [flow('rec-11', 11, HealthFlowValue.medium)],
          nextCursor: 'page-2',
        ),
        const HealthReadResult.permissionDenied(),
      ]);

      await expectNothingRemoved(await removeOffered());
    });

    test('whose first page the store will not let be read', () async {
      await offered();
      store.wholeHistoryAgainPages
          .add(const HealthReadResult.permissionDenied());

      await expectNothingRemoved(await removeOffered());
    });

    // An import treats that as "no data" and says so. A removal that
    // could not make its first read was stopped, and must say that.
    test('whose first read of all the store will not let be made',
        () async {
      await offered();
      store.changePages.add(const HealthReadResult.permissionDenied());

      await expectNothingRemoved(await removeOffered());
      expect(store.askedForWholeHistory, isNot(contains(true)));
    });

    test('an import the store will not let read is still "no data", not '
        'a stopped pass', () async {
      await offered();
      store.changePages.add(const HealthReadResult.permissionDenied());

      final summary = await import.importNow();

      expect(summary.isBlocked, isFalse);
      expect(summary.isEmpty, isTrue);
    });

    // The read of everything drops the stored position, and the pages
    // nobody read hang on it: their deletions would never be reported.
    test('is not started after a changes read that was cut short',
        () async {
      await offered();
      store.changePages.addAll([
        HealthReadResult.samples(
          const [],
          incremental: true,
          nextCursor: 'page-2',
        ),
        const HealthReadResult.failed('the store went away'),
      ]);

      await expectNothingRemoved(await removeOffered());
      expect(store.askedForWholeHistory, isNot(contains(true)));
    });

    test('an import that would read everything again does not, after a '
        'changes read that was cut short', () async {
      await offered();
      store.changePages.addAll([
        HealthReadResult.samples(
          [flow('rec-20', 20, HealthFlowValue.medium)],
          incremental: true,
          nextCursor: 'page-2',
        ),
        HealthReadResult.samples(
          const [],
          incremental: true,
          deletedRecordIds: const ['rec-20'],
          nextCursor: 'page-3',
        ),
        const HealthReadResult.failed('the store went away'),
      ]);

      final summary = await import.importNow();

      expect(summary.isBlocked, isTrue);
      expect(store.askedForWholeHistory, isNot(contains(true)));
      expect(await dayOn(20), isNull, reason: 'its record was deleted');
      expect(store.commits, isEmpty);
    });

    test('that runs into the page limit', () async {
      await offered();
      store.wholeHistoryAgainPages.addAll([
        for (var page = 0; page < kHealthImportMaxPages; page++)
          HealthReadResult.samples(const [], nextCursor: 'page-$page'),
      ]);

      await expectNothingRemoved(await removeOffered());
      expect(store.wholeHistoryAgainPages, isEmpty, reason: 'all were read');
    });

    test('whose cursor comes round again', () async {
      await offered();
      store.wholeHistoryAgainPages.addAll([
        HealthReadResult.samples(const [], nextCursor: 'same'),
        HealthReadResult.samples(const [], nextCursor: 'same'),
      ]);

      await expectNothingRemoved(await removeOffered());
    });

    test('and she can ask again once the store can be read', () async {
      await offered();
      store.wholeHistoryAgainPages
          .add(const HealthReadResult.unavailable());
      await removeOffered();

      final summary = await removeOffered();

      expect(summary.daysRemoved, 1);
      expect(await dayOn(10), isNull);
      expect(await onOffer(), 0);
    });
  });

  group('a spotting entry whose record was deleted', () {
    test('goes, and so does the day the import made to hang it on', () async {
      await imported([_spotting('spot-11', 11)]);
      expect(await entriesOn(11), hasLength(1));
      await deletedInStore(['spot-11']);
      expect(await onOffer(), 1);

      final summary = await removeOffered();

      expect(await dayOn(11), isNull);
      expect(summary.daysRemoved, 1);
      // The store held nothing else, so the removal is all the pass did.
      // It is not a pass that did nothing.
      expect(summary.samplesRead, 0);
      expect(summary.isEmpty, isFalse);
      expect(await days.deletedHealthRecords(_profileId), isEmpty);
    });

    test('an entry that lands on the day it hangs on, in the middle of the '
        'removal, keeps that day', () async {
      await imported([_spotting('spot-11', 11)]);
      await deletedInStore(['spot-11']);
      final hooked = _HookedDays(days)
        ..beforeNextFind = () async {
          final day = (await dayOn(11))!;
          await observations.save(
            Observation(
              id: '',
              dayEntryId: day.id,
              profileId: _profileId,
              localDate: day.localDate,
              tz: day.tz,
              category: ObservationCategory.pain,
              code: 'cramps',
              intensity: 3,
              updatedAt: DateTime.utc(2026, 9, 11, 13),
            ),
          );
        };

      await removeOffered(serviceOver(hooked));

      expect(hooked.beforeNextFind, isNull, reason: 'the entry landed');
      expect(await dayOn(11), isNotNull);
      expect((await entriesOn(11)).map((entry) => entry.code), ['cramps']);
    });

    test('goes and leaves the day when the day has a flow', () async {
      await imported([
        flow('rec-11', 11, HealthFlowValue.light),
        _spotting('spot-11', 11),
      ]);
      await deletedInStore(['spot-11']);

      await removeOffered();

      expect((await dayOn(11))!.flow, FlowLevel.light);
      expect(await entriesOn(11), isEmpty);
    });

    test('goes and leaves the day when she has put a tag on it', () async {
      await imported([_spotting('spot-11', 11)]);
      await days.save((await dayOn(11))!.copyWith(tags: const ['headache']));
      await deletedInStore(['spot-11']);

      await removeOffered();

      expect((await dayOn(11))!.tags, ['headache']);
      expect(await entriesOn(11), isEmpty);
    });

    test('with the flow record of the same day deleted too, the day goes',
        () async {
      await imported([
        flow('rec-11', 11, HealthFlowValue.light),
        _spotting('spot-11', 11),
      ]);
      await deletedInStore(['spot-11', 'rec-11']);

      final summary = await removeOffered();

      expect(await dayOn(11), isNull);
      expect(summary.daysRemoved, 1, reason: 'one day, counted once');
    });

    test('a flow record deleted leaves the day while its imported spotting '
        'entry is still in the store', () async {
      await imported([
        flow('rec-11', 11, HealthFlowValue.light),
        _spotting('spot-11', 11),
      ]);
      await deletedInStore(['rec-11']);

      await removeOffered();

      expect((await dayOn(11))!.flow, FlowLevel.none);
      expect(await entriesOn(11), hasLength(1));
    });

    // The day goes with the entry only when the import made it for the
    // entry: this store's source, no record, no flow. Each of the three
    // is a day that is not the import's to remove.
    for (final (what, host) in <(String, DayEntry Function(DayEntry))>[
      ('she made herself', (day) => day),
      (
        'that names a record still in the store',
        (day) => day.copyWith(
              source: _daySourceOf(platform),
              sourceId: 'rec-other@1',
            ),
      ),
      (
        'of this store\'s that she has since given a flow',
        (day) => day.copyWith(
              source: _daySourceOf(platform),
              flow: FlowLevel.light,
            ),
      ),
    ]) {
      test('goes and leaves a day $what', () async {
        final made = await days.save(
          host(
            DayEntry(
              id: '',
              profileId: _profileId,
              localDate: sept(11),
              tz: 'America/New_York',
              flow: FlowLevel.none,
              updatedAt: DateTime.utc(2026, 9, 11, 13),
            ),
          ),
        );
        await imported([_spotting('spot-11', 11)]);
        expect(await entriesOn(11), hasLength(1));
        await deletedInStore(['spot-11']);

        final summary = await removeOffered();

        final day = (await dayOn(11))!;
        expect(day.id, made.id);
        expect(day.source, made.source);
        expect(day.sourceId, made.sourceId);
        expect(day.flow, made.flow);
        expect(await entriesOn(11), isEmpty);
        expect(summary.daysRemoved, 1);
      });
    }

    test('a spotting entry from another source that carries the same id is '
        'not offered and not touched', () async {
      await imported([flow('rec-11', 11, HealthFlowValue.light)]);
      final day = (await dayOn(11))!;
      await observations.save(
        Observation(
          id: '',
          dayEntryId: day.id,
          profileId: _profileId,
          localDate: day.localDate,
          tz: day.tz,
          category: ObservationCategory.spotting,
          code: ObservationCategory.spotting.wireCode,
          source: ObservationSource.clueImport,
          sourceId: 'spot-11',
          updatedAt: DateTime.utc(2026, 9, 11, 13),
        ),
      );

      await deletedInStore(['spot-11']);

      expect(await onOffer(), 0);
      await removeOffered();
      expect(await entriesOn(11), hasLength(1));
    });

    group('scan counts on an unanswered offer (Issue #1622)', () {
      test(
          'a pass with no modifications loads rows once, not twice',
          () async {
        await imported([
          flow('rec-10', 10, HealthFlowValue.heavy),
          flow('rec-11', 11, HealthFlowValue.medium),
        ]);
        await deletedInStore(['rec-10']);
        expect(await onOffer(), 1);

        final countingDays = _CountingDayEntries(days);
        final countingObs = _CountingObservations(observations);
        final countingService = LocalHealthImportService(
          importPlatform: platform,
          platform: _Platform(),
          source: store,
          binding: binding,
          minorBindingAllowed: false,
          profiles: profiles,
          dayEntries: countingDays,
          observations: countingObs,
          guardiansForProfile: (_) async => [
            ProfileGuardian(
              id: 'g1',
              profileId: _profileId,
              userId: _ownerId,
              role: GuardianRole.primaryGuardian,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
          signedInUserId: () => _ownerId,
          today: () => LocalDate(2026, 9, 30),
        );

        await countingService.importNow();

        expect(countingDays.listCalls, 1);
        expect(countingObs.listCalls, 1);
        expect(await onOffer(), 1);
      });

      test(
          'a pass with writes on unrelated dates does not reload rows for the trim',
          () async {
        await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
        await deletedInStore(['rec-10']);
        expect(await onOffer(), 1);

        store.write(flow('rec-20', 20, HealthFlowValue.light));

        final countingDays = _CountingDayEntries(days);
        final countingObs = _CountingObservations(observations);
        final countingService = LocalHealthImportService(
          importPlatform: platform,
          platform: _Platform(),
          source: store,
          binding: binding,
          minorBindingAllowed: false,
          profiles: profiles,
          dayEntries: countingDays,
          observations: countingObs,
          guardiansForProfile: (_) async => [
            ProfileGuardian(
              id: 'g1',
              profileId: _profileId,
              userId: _ownerId,
              role: GuardianRole.primaryGuardian,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
          signedInUserId: () => _ownerId,
          today: () => LocalDate(2026, 9, 30),
        );

        await countingService.importNow();

        expect(countingDays.listCalls, 1);
        expect(countingObs.listCalls, 1);
        expect(await onOffer(), 1);
        expect((await dayOn(20))?.flow, FlowLevel.light);
      });

      test(
          'a pass that modifies the deleted day reloads rows and trims the offer',
          () async {
        await imported([flow('rec-10', 10, HealthFlowValue.heavy)]);
        await deletedInStore(['rec-10']);
        expect(await onOffer(), 1);

        store.write(flow('rec-replacement-10', 10, HealthFlowValue.medium,
            modifiedHour: 15));

        final countingDays = _CountingDayEntries(days);
        final countingObs = _CountingObservations(observations);
        final countingService = LocalHealthImportService(
          importPlatform: platform,
          platform: _Platform(),
          source: store,
          binding: binding,
          minorBindingAllowed: false,
          profiles: profiles,
          dayEntries: countingDays,
          observations: countingObs,
          guardiansForProfile: (_) async => [
            ProfileGuardian(
              id: 'g1',
              profileId: _profileId,
              userId: _ownerId,
              role: GuardianRole.primaryGuardian,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
          signedInUserId: () => _ownerId,
          today: () => LocalDate(2026, 9, 30),
        );

        await countingService.importNow();

        expect(countingDays.listCalls, 2);
        expect(countingObs.listCalls, 2);
        expect(await onOffer(), 0);
      });
    });
  });
}

class _CountingDayEntries
    implements DayEntriesRepository, DeletedDayEntryReader {
  _CountingDayEntries(this._inner);
  final DayEntriesRepository _inner;
  int listCalls = 0;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) {
    listCalls++;
    return _inner.listForProfile(profileId);
  }

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) =>
      _inner.find(profileId, localDate);

  @override
  Future<DayEntry> save(DayEntry entry) => _inner.save(entry);

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);

  @override
  Future<Map<String, DateTime>> deletedHealthRecords(String profileId) =>
      (_inner as DeletedDayEntryReader).deletedHealthRecords(profileId);

  @override
  Future<void> forgetDeletedHealthRecords(
    String profileId,
    Map<String, DateTime> records,
  ) =>
      (_inner as DeletedDayEntryReader)
          .forgetDeletedHealthRecords(profileId, records);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _CountingObservations implements ObservationsRepository {
  _CountingObservations(this._inner);
  final ObservationsRepository _inner;
  int listCalls = 0;

  @override
  Future<List<Observation>> listForProfile(String profileId) {
    listCalls++;
    return _inner.listForProfile(profileId);
  }

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) =>
      _inner.listForDayEntry(dayEntryId);

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(String dayEntryId) =>
      _inner.listForDayEntryWithLegacyAlias(dayEntryId);

  @override
  Future<Observation> save(Observation observation) =>
      _inner.save(observation);

  @override
  Future<void> delete(String id) => _inner.delete(id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
