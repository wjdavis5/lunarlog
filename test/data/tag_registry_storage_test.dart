/// Issue #257: `LunarLogStorage`'s profile_tag_registry API and the
/// [DriftTagRegistryRepository] surface over it — create/rename/retire
/// with dirty/local_rev bookkeeping, the live-rows-only read, `readDirty`
/// keyset paging, the codec round trip (drift row -> `sync_push` JSON ->
/// [RemoteProfileTagRegistryRow] -> local apply), and retirement's
/// picker-removal-without-deletion contract. Mirrors
/// `storage_care_content_test.dart`'s shape.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_tag_registry_repository.dart';
import 'package:lunarlog/data/sync/row_codec.dart';

/// A real ULID: the codec validates ids (encode throws on a non-ULID
/// profile_id), so the storage tests run under a ULID-shaped profile id.
const String profileUlid = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late FixedClock clock;
  late LunarLogStorage storage;
  late DriftTagRegistryRepository repository;

  final t0 = DateTime.utc(2026, 9, 1, 8);
  final t1 = DateTime.utc(2026, 9, 2, 8);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    await storage.upsertProfile(
        id: profileUlid, displayName: 'Riley', isMinor: true, updatedAt: t0);
    repository = DriftTagRegistryRepository(storage);
  });

  test('create derives the code, stores the label, marks the row dirty',
      () async {
    final created = await repository.create(
      profileId: profileUlid,
      label: 'BACK PAIN',
    );
    expect(created.code, 'back_pain');
    expect(created.displayName, 'BACK PAIN');
    expect(created.category, 'custom');
    expect(created.offered, isTrue);

    final dirty = await storage.readDirtyProfileTagRegistry();
    expect(dirty.map((row) => row.id), [created.id]);
    expect(dirty.first.localRev, 1);
    expect(dirty.first.dirty, isTrue);
  });

  test('rename rewrites the label only — the code is immutable', () async {
    final created = await repository.create(
      profileId: profileUlid,
      label: 'Back cracking',
    );
    clock.now = t1;
    final renamed = await repository.rename(
      tagId: created.id,
      label: 'Back cracking (upper)',
    );
    expect(renamed.code, 'back_cracking');
    expect(renamed.displayName, 'Back cracking (upper)');
    final reread = await repository.listForProfile(profileUlid);
    expect(reread.single.displayName, 'Back cracking (upper)');
  });

  test('retire sets hidden_at and nothing else — never a deletion',
      () async {
    final created = await repository.create(
      profileId: profileUlid,
      label: 'Vulva pain?!',
    );
    clock.now = t1;
    expect(await storage.retireProfileTagRegistryEntry(created.id), isTrue);

    final rows = await repository.listForProfile(profileUlid);
    expect(rows, hasLength(1),
        reason: 'a retired tag stays in the registry (it still resolves '
            'stored codes to display names)');
    final retired = rows.single;
    expect(retired.offered, isFalse);
    expect(retired.renders, isTrue);
    expect(retired.hiddenAt, t1);
    expect(retired.deletedAt, isNull);
    expect(retired.displayName, 'Vulva pain?!');
  });

  test('listForProfile excludes tombstones, includes retired entries',
      () async {
    final a = await repository.create(profileId: profileUlid, label: 'Keep');
    final b = await repository.create(profileId: profileUlid, label: 'Retire me');
    await storage.retireProfileTagRegistryEntry(b.id);
    // A remote tombstone for a.
    await storage.applyRemoteProfileTagRegistryEntry(
      RemoteProfileTagRegistryRow(
        id: a.id,
        profileId: profileUlid,
        code: 'keep',
        displayName: 'Keep',
        category: 'custom',
        createdAt: t0,
        updatedAt: t1,
        deletedAt: t1,
      ),
    );
    final rows = await repository.listForProfile(profileUlid);
    expect(rows.map((row) => row.code), ['retire_me']);
  });

  test('an invalid label or unknown id throws ArgumentError', () async {
    await expectLater(
      repository.create(profileId: profileUlid, label: '?!'),
      throwsArgumentError,
    );
    final created = await repository.create(
      profileId: profileUlid,
      label: 'Valid',
    );
    await expectLater(
      repository.rename(tagId: created.id, label: ''),
      throwsArgumentError,
    );
    await expectLater(
      repository.rename(tagId: 'missing', label: 'Whatever'),
      throwsArgumentError,
    );
  });

  group('codec + remote apply round trip', () {
    test('a locally created row encodes exactly the p_tag_registry shape',
        () async {
      final created = await repository.create(
        profileId: profileUlid,
        label: 'Back cracking',
      );
      final dirty = await storage.readDirtyProfileTagRegistry();
      final encoded = encodeProfileTagRegistryEntry(dirty.single);
      expect(encoded['id'], created.id);
      expect(encoded['profile_id'], profileUlid);
      expect(encoded['code'], 'back_cracking');
      expect(encoded['display_name'], 'Back cracking');
      expect(encoded['category'], 'custom');
      expect(encoded.containsKey('created_by'), isFalse,
          reason: 'the server stamps created_by; a row carrying the key '
              'is rejected as unknown');
      expect(encoded.containsKey('created_at'), isFalse);
    });

    test('decode -> applyRemote lands the row clean (not dirty, never '
        'pushed back)', () async {
      const id = '01J8ZQ9K7MC2X3V4B5N6P7Q8T1';
      final decoded = decodeProfileTagRegistryEntry({
        'id': id,
        'profile_id': profileUlid,
        'code': 'peer_tag',
        'display_name': 'Peer tag',
        'category': 'custom',
        'intensity_enabled': true,
        'hidden_at': null,
        'sort_order': 3,
        'created_by': '00000000-0000-0000-0000-000000000001',
        'created_at': '2026-09-01T08:00:00.000Z',
        'updated_at': '2026-09-02T08:00:00.000Z',
        'deleted_at': null,
        'server_version': 5,
      });
      expect(decoded.table, SyncTable.profileTagRegistry);
      expect(decoded.serverVersion, 5);
      expect(await storage.applyRemoteProfileTagRegistryEntry(decoded),
          isTrue);

      final rows = await repository.listForProfile(profileUlid);
      expect(rows.single.code, 'peer_tag');
      expect(rows.single.displayName, 'Peer tag');
      expect(rows.single.intensityEnabled, isTrue);
      // createdBy/createdAt ride the stored row (display attribution);
      // the domain model deliberately does not carry them.
      final stored =
          await storage.getProfileTagRegistryEntriesById(decoded.id);
      expect(
          stored!.createdBy, '00000000-0000-0000-0000-000000000001');
      expect(
        await storage.readDirtyProfileTagRegistry(),
        isEmpty,
        reason: 'a pulled server copy is never pushed back',
      );
    });

    test('a remote tombstone applies payload-cleared (code survives)',
        () async {
      final created = await repository.create(
        profileId: profileUlid,
        label: 'Doomed',
      );
      final applied = await storage.applyRemoteProfileTagRegistryEntry(
        RemoteProfileTagRegistryRow(
          id: created.id,
          profileId: profileUlid,
          code: 'doomed',
          displayName: '',
          category: '',
          createdAt: t0,
          updatedAt: t1,
          deletedAt: t1,
        ),
      );
      expect(applied, isTrue);
      expect(await repository.listForProfile(profileUlid), isEmpty);
      // The stored row itself keeps its code for re-import recognition.
      final stored =
          await storage.getProfileTagRegistryEntriesById(created.id);
      expect(stored!.deletedAt, isNotNull);
      expect(stored.code, 'doomed');
    });
  });

  group('Issue #825: same-code deduplication', () {
    test('findProfileTagByCode looks up live tag case-insensitively',
        () async {
      final created = await repository.create(
        profileId: profileUlid,
        label: 'Back cracking',
      );
      final matchLower =
          await storage.findProfileTagByCode(profileUlid, 'back_cracking');
      expect(matchLower?.id, created.id);

      final matchUpper =
          await storage.findProfileTagByCode(profileUlid, 'BACK_CRACKING');
      expect(matchUpper?.id, created.id);

      final matchOtherProfile =
          await storage.findProfileTagByCode('other-profile-id', 'back_cracking');
      expect(matchOtherProfile, isNull);

      // Tombstone is excluded
      await storage.applyRemoteProfileTagRegistryEntry(
        RemoteProfileTagRegistryRow(
          id: created.id,
          profileId: profileUlid,
          code: 'back_cracking',
          displayName: '',
          category: '',
          createdAt: t0,
          updatedAt: t1,
          deletedAt: t1,
        ),
      );
      final matchAfterTombstone =
          await storage.findProfileTagByCode(profileUlid, 'back_cracking');
      expect(matchAfterTombstone, isNull);
    });

    test(
        'upsertProfileTagRegistryEntry with id: null reuses existing live row with same code',
        () async {
      final first = await storage.upsertProfileTagRegistryEntry(
        profileId: profileUlid,
        code: 'cramps',
        displayName: 'Cramps',
      );
      expect(first.localRev, 1);

      // Second write with id: null and same code (case-insensitive) reuses first.id
      final second = await storage.upsertProfileTagRegistryEntry(
        profileId: profileUlid,
        code: 'CRAMPS',
        displayName: 'Severe Cramps',
      );
      expect(second.id, first.id);
      expect(second.displayName, 'Severe Cramps');
      expect(second.localRev, 2);

      final rows = await storage.getProfileTagRegistry(profileUlid);
      expect(rows, hasLength(1));
      expect(rows.single.id, first.id);
      expect(rows.single.displayName, 'Severe Cramps');
    });

    test(
        'upsertProfileTagRegistryEntry un-retires existing retired row when re-created',
        () async {
      final first = await storage.upsertProfileTagRegistryEntry(
        profileId: profileUlid,
        code: 'nausea',
        displayName: 'Nausea',
        hiddenAt: t0,
      );
      expect(first.hiddenAt, isNotNull);

      final second = await storage.upsertProfileTagRegistryEntry(
        profileId: profileUlid,
        code: 'nausea',
        displayName: 'Nausea (un-retired)',
        hiddenAt: null,
      );
      expect(second.id, first.id);
      expect(second.hiddenAt, isNull);
      expect(second.displayName, 'Nausea (un-retired)');
    });

    test(
        'upsertProfileTagRegistryEntry does not reuse tombstoned row, mints new id',
        () async {
      final first = await storage.upsertProfileTagRegistryEntry(
        profileId: profileUlid,
        code: 'bloating',
        displayName: 'Bloating',
      );
      // Tombstone first
      await storage.applyRemoteProfileTagRegistryEntry(
        RemoteProfileTagRegistryRow(
          id: first.id,
          profileId: profileUlid,
          code: 'bloating',
          displayName: '',
          category: '',
          createdAt: t0,
          updatedAt: t1,
          deletedAt: t1,
        ),
      );

      final second = await storage.upsertProfileTagRegistryEntry(
        profileId: profileUlid,
        code: 'bloating',
        displayName: 'Bloating (reborn)',
      );
      expect(second.id, isNot(equals(first.id)));
      expect(second.deletedAt, isNull);

      final all = await storage.getProfileTagRegistryEntriesById(first.id);
      expect(all!.deletedAt, isNotNull);
      final live = await storage.getProfileTagRegistry(profileUlid);
      expect(live, hasLength(1));
      expect(live.single.id, second.id);
    });
  });
}
