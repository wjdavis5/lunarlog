/// Issue #1594 end to end: a record deleted in the health store, over the
/// real repositories and a real database.
///
/// The import removes rows here, and the storage layer notes every row
/// removed on this phone as something she deleted (Issue #1561). Only a
/// real database shows whether the two agree: that what the import takes
/// out on the store's say-so is not then held against the store.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
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

const _profileId = 'p1';
const _ownerId = 'owner-user';

class _Platform implements HealthPlatformStore {
  @override
  Future<HealthPlatformResult> bindProfile(HealthGuardFacts facts) async =>
      const HealthPlatformAllowed();

  @override
  Future<HealthPlatformResult> requestImportAuthorization(
    HealthGuardFacts facts,
  ) async =>
      const HealthPlatformAllowed();

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
    if (wholeHistory) {
      hasPosition = false;
      await onWholeHistoryAgain?.call();
    }
    if (hasPosition && changePages.isNotEmpty) return changePages.removeAt(0);
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

/// A flow record on September [day] 2026, local midnight at UTC-4. Health
/// Connect changes a record in place, so it carries when it last did.
HealthFlowSample _flow(
  String id,
  int day,
  HealthFlowValue flow, {
  int modifiedHour = 12,
}) {
  final start = DateTime.utc(2026, 9, day, 4);
  return HealthFlowSample(
    recordId: id,
    flow: flow,
    start: start,
    end: start.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
    offset: const Duration(hours: -4),
    modifiedAt: DateTime.utc(2026, 9, day, modifiedHour),
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftDayEntriesRepository days;
  late DriftObservationsRepository observations;
  late _Store store;
  late LocalHealthImportService import;

  LocalDate sept(int day) => LocalDate(2026, 9, day);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    days = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
    final profiles = DriftProfilesRepository(db.storage);
    await db.storage.upsertProfile(
      id: _profileId,
      displayName: 'Ada',
      isMinor: false,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final binding = HealthSyncBinding(DriftSettingsStore(db.storage));
    await binding.bind(
      profile: (await profiles.findById(_profileId))!,
      signedInUserId: _ownerId,
      ownerUserId: _ownerId,
      minorBindingAllowed: false,
    );
    store = _Store();
    import = LocalHealthImportService(
      importPlatform: HealthImportPlatform.healthConnect,
      platform: _Platform(),
      source: store,
      binding: binding,
      minorBindingAllowed: false,
      profiles: profiles,
      dayEntries: days,
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

  group('a record deleted in the store', () {
    test('takes its imported day out, after everything has been read again',
        () async {
      await imported([
        _flow('rec-10', 10, HealthFlowValue.heavy),
        _flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);

      store.delete('rec-10');
      final summary = await import.importNow();

      expect(await dayOn(10), isNull);
      expect((await dayOn(11))!.flow, FlowLevel.medium);
      expect(summary.daysRemoved, 1);
      expect(summary.storeDeletionsKept, 0);
      expect(summary.isEmpty, isFalse);
      // A changes read found the deletion; a whole-history read followed,
      // and it is that one's position the pass commits.
      expect(store.askedForWholeHistory, [false, true]);
      expect(store.commits, ['whole']);
    });

    test('is not remembered as a day she deleted, so the same record is '
        'imported if the store offers it again', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      store.delete('rec-10');
      await import.importNow();
      expect(await dayOn(10), isNull);
      expect(await days.deletedHealthRecords(_profileId), isEmpty);

      store.write(_flow('rec-10', 10, HealthFlowValue.medium, modifiedHour: 18));
      await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.medium);
    });

    test('a day she deleted herself is still remembered afterwards', () async {
      await imported([
        _flow('rec-10', 10, HealthFlowValue.heavy),
        _flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      await days.delete(_profileId, sept(11));
      final hers = await days.deletedHealthRecords(_profileId);
      expect(hers, hasLength(1));

      store.delete('rec-10');
      await import.importNow();

      expect(await days.deletedHealthRecords(_profileId), hers);
      expect(await dayOn(11), isNull, reason: 'and her deletion still holds');
    });

    test('leaves the day when it carries a tag of hers, and takes only the '
        'flow', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save((await dayOn(10))!.copyWith(tags: const ['cramps']));

      store.delete('rec-10');
      final summary = await import.importNow();

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
    ]) {
      test('leaves the day when it carries $what', () async {
        await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
        await days.save(change((await dayOn(10))!));

        store.delete('rec-10');
        await import.importNow();

        expect((await dayOn(10))!.flow, FlowLevel.none);
      });
    }

    test('leaves the day when it carries an entry of hers', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
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

      store.delete('rec-10');
      await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.none);
      expect(await entriesOn(10), hasLength(1));
    });

    test('a day left with no flow takes one from the store again', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save((await dayOn(10))!.copyWith(tags: const ['cramps']));
      store.delete('rec-10');
      await import.importNow();

      store.write(_flow('rec-10b', 10, HealthFlowValue.light));
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
        _flow('rec-heavy', 10, HealthFlowValue.heavy),
        _flow('rec-light', 10, HealthFlowValue.light),
      ]);
      expect((await dayOn(10))!.flow, FlowLevel.heavy);

      store.delete('rec-heavy');
      final summary = await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.light);
      expect(summary.daysRemoved, 1);
      expect(summary.daysWritten, 1);
    });

    test('a day she corrected after importing it goes too: the record going '
        'is the store\'s news about that day', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      await days.save((await dayOn(10))!.copyWith(flow: FlowLevel.light));

      store.delete('rec-10');
      await import.importNow();

      expect(await dayOn(10), isNull);
    });

    test('a day she logged herself is never touched', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
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

      store.delete('rec-10');
      await import.importNow();

      expect((await dayOn(12))!.flow, FlowLevel.medium);
    });

    // The same id under another source is another record: a file import's
    // row, or one from another kind of store.
    test('a day from another source that carries the same id is not this '
        'store\'s, and is never touched', () async {
      await imported([_flow('rec-11', 11, HealthFlowValue.medium)]);
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

      store.delete('rec-12');
      final summary = await import.importNow();

      expect((await dayOn(12))!.flow, FlowLevel.heavy);
      expect(summary.daysRemoved, 0);
      expect(store.askedForWholeHistory, [false]);
    });

    // The whole history is read between finding the row and removing it.
    test('a day whose row names another record by the time it is to be '
        'removed is left as it is', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      final row = (await dayOn(10))!;
      store
        ..delete('rec-10')
        ..onWholeHistoryAgain = () async {
          await days.save(row.copyWith(sourceId: 'rec-other@1'));
        };

      final summary = await import.importNow();

      final day = (await dayOn(10))!;
      expect(day.flow, FlowLevel.heavy);
      expect(day.sourceId, 'rec-other@1');
      expect(summary.daysRemoved, 0);
    });

    test('a deleted record lunarlog imported nothing from changes nothing, '
        'and nothing is read again', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);

      store.delete('one-of-lunarlogs-own-writes');
      final summary = await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(summary.daysRemoved, 0);
      expect(summary.isEmpty, isTrue);
      expect(store.askedForWholeHistory, [false]);
      expect(store.commits, ['changes']);
    });
  });

  group('a spotting entry whose record was deleted', () {
    test('goes, and so does the day the import made to hang it on', () async {
      await imported([_spotting('spot-11', 11)]);
      expect(await entriesOn(11), hasLength(1));

      store.delete('spot-11');
      final summary = await import.importNow();

      expect(await dayOn(11), isNull);
      expect(summary.daysRemoved, 1);
      expect(await days.deletedHealthRecords(_profileId), isEmpty);
    });

    test('goes and leaves the day when the day has a flow', () async {
      await imported([
        _flow('rec-11', 11, HealthFlowValue.light),
        _spotting('spot-11', 11),
      ]);

      store.delete('spot-11');
      await import.importNow();

      expect((await dayOn(11))!.flow, FlowLevel.light);
      expect(await entriesOn(11), isEmpty);
    });

    test('goes and leaves the day when she has put a tag on it', () async {
      await imported([_spotting('spot-11', 11)]);
      await days.save((await dayOn(11))!.copyWith(tags: const ['headache']));

      store.delete('spot-11');
      await import.importNow();

      expect((await dayOn(11))!.tags, ['headache']);
      expect(await entriesOn(11), isEmpty);
    });

    test('with the flow record of the same day deleted too, the day goes',
        () async {
      await imported([
        _flow('rec-11', 11, HealthFlowValue.light),
        _spotting('spot-11', 11),
      ]);

      store
        ..delete('spot-11')
        ..delete('rec-11');
      final summary = await import.importNow();

      expect(await dayOn(11), isNull);
      expect(summary.daysRemoved, 1, reason: 'one day, counted once');
    });

    test('a spotting entry from another source that carries the same id is '
        'never touched', () async {
      await imported([_flow('rec-11', 11, HealthFlowValue.light)]);
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

      store.delete('spot-11');
      final summary = await import.importNow();

      expect(await entriesOn(11), hasLength(1));
      expect(summary.daysRemoved, 0);
      expect(store.askedForWholeHistory, [false]);
    });

    test('a flow record deleted leaves the day while its imported spotting '
        'entry is still in the store', () async {
      await imported([
        _flow('rec-11', 11, HealthFlowValue.light),
        _spotting('spot-11', 11),
      ]);

      store.delete('rec-11');
      await import.importNow();

      expect((await dayOn(11))!.flow, FlowLevel.none);
      expect(await entriesOn(11), hasLength(1));
    });
  });

  group('how far the store is followed', () {
    Future<void> importedDays(int count) => imported([
          for (var day = 1; day <= count; day++)
            _flow('rec-$day', day, HealthFlowValue.medium),
        ]);

    test('up to $kHealthImportMaxMirroredDeletions days in one pass',
        () async {
      await importedDays(kHealthImportMaxMirroredDeletions);
      for (var day = 1; day <= kHealthImportMaxMirroredDeletions; day++) {
        store.delete('rec-$day');
      }

      final summary = await import.importNow();

      expect(summary.daysRemoved, kHealthImportMaxMirroredDeletions);
      expect(summary.storeDeletionsKept, 0);
      expect(await days.listForProfile(_profileId), isEmpty);
    });

    // Someone clearing out Health Connect after moving to lunarlog. Nothing
    // in a deletion tells that from a correction, so past the limit every
    // day is kept and the result says how many.
    test('one more than that, and every day is kept', () async {
      const count = kHealthImportMaxMirroredDeletions + 1;
      await importedDays(count);
      for (var day = 1; day <= count; day++) {
        store.delete('rec-$day');
      }

      final summary = await import.importNow();

      expect(summary.daysRemoved, 0);
      expect(summary.storeDeletionsKept, count);
      expect(summary.isEmpty, isFalse);
      expect(await days.listForProfile(_profileId), hasLength(count));
      expect(store.askedForWholeHistory, [false],
          reason: 'nothing is read again when nothing is to be removed');
      expect(store.commits, ['changes']);

      // The store reports a deletion once. The days stay from then on.
      final later = await import.importNow();
      expect(later.storeDeletionsKept, 0);
      expect(await days.listForProfile(_profileId), hasLength(count));
    });

    test('a record a whole-history read does not return is not a deleted '
        'record', () async {
      await imported([
        _flow('rec-10', 10, HealthFlowValue.heavy),
        _flow('rec-11', 11, HealthFlowValue.medium),
      ]);
      // Hidden, as with "Access past data" off: gone from what a read
      // returns, and no deletion reported.
      store.records.remove('rec-10');
      store.hasPosition = false;

      final summary = await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(summary.daysRemoved, 0);
    });

    test('only a changes page can say a record was deleted', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      store
        ..hasPosition = false
        ..deletedOnWholeHistoryPage = const ['rec-10'];

      final summary = await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(summary.daysRemoved, 0);
    });

    // Pages come in the order things happened.
    test('a record deleted on one page and written again on a later one is '
        'in the store: its day stays and takes the new value', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      store.changePages.addAll([
        HealthReadResult.samples(
          const [],
          incremental: true,
          deletedRecordIds: const ['rec-10'],
          nextCursor: 'page-2',
        ),
        HealthReadResult.samples(
          [_flow('rec-10', 10, HealthFlowValue.medium, modifiedHour: 18)],
          incremental: true,
          commitToken: 'changes',
        ),
      ]);

      final summary = await import.importNow();

      expect((await dayOn(10))!.flow, FlowLevel.medium);
      expect(summary.daysRemoved, 0);
      expect(store.requests, [(null, false), ('page-2', false)]);
    });

    test('a record written on one page and deleted on a later one is gone',
        () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      store.records.remove('rec-10');
      store.changePages.addAll([
        HealthReadResult.samples(
          [_flow('rec-10', 10, HealthFlowValue.medium, modifiedHour: 18)],
          incremental: true,
          nextCursor: 'page-2',
        ),
        HealthReadResult.samples(
          const [],
          incremental: true,
          deletedRecordIds: const ['rec-10'],
          commitToken: 'changes',
        ),
      ]);

      final summary = await import.importNow();

      expect(await dayOn(10), isNull);
      expect(summary.daysRemoved, 1);
    });

    // Asking again on a later page would start the read over each time.
    test('only the first page of the second read asks for the whole history',
        () async {
      await imported([
        _flow('rec-10', 10, HealthFlowValue.heavy),
        _flow('rec-11', 11, HealthFlowValue.medium),
        _flow('rec-12', 12, HealthFlowValue.light),
      ]);
      store
        ..delete('rec-10')
        ..wholeHistoryPaged = true;

      final summary = await import.importNow();

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

    test('when everything cannot be read again, nothing is removed', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      store
        ..delete('rec-10')
        ..onWholeHistoryAgain = () async {
          store.wholeHistoryAnswer = const HealthReadResult.unavailable();
        };

      final summary = await import.importNow();

      expect(summary.blocked, isA<HealthPlatformUnavailable>());
      expect((await dayOn(10))!.flow, FlowLevel.heavy);
      expect(store.commits, isEmpty);
    });

    test('a day she deletes herself while the store is being read again is '
        'hers: it is not counted, and stays remembered', () async {
      await imported([_flow('rec-10', 10, HealthFlowValue.heavy)]);
      store
        ..delete('rec-10')
        ..onWholeHistoryAgain = () => days.delete(_profileId, sept(10));

      final summary = await import.importNow();

      expect(summary.daysRemoved, 0);
      expect(await days.deletedHealthRecords(_profileId), hasLength(1));
    });
  });
}
