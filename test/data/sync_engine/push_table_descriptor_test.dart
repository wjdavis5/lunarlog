/// Issue #551: guards the table-driven push descriptor — the single ordered
/// list that replaced `_PushCursor`'s nine hand-copied page readers and the
/// hand-written `_readPushRound` chain.
///
/// The first test pins the push paging order as a literal so a reorder is a
/// conscious change (parent-before-child: profiles, then day entries, then
/// everything that only references a profile). The second cross-checks the
/// descriptor against the storage layer's own pushable-table set, so a
/// newly synced table cannot be added on one side without the other — the
/// per-table omission bug class (#825) the refactor exists to close.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/storage.dart' show SyncTable;

import 'sync_engine_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('the push descriptor is exactly the parent-before-child paging order',
      () {
    final rig = Rig();
    addTearDown(rig.dispose);

    expect(rig.engine.pushTableOrderForTest(), const [
      SyncTable.profiles,
      SyncTable.dayEntries,
      SyncTable.observations,
      SyncTable.profileModes,
      SyncTable.cycleOverrides,
      SyncTable.careNotes,
      SyncTable.visitPrepItems,
      SyncTable.guardianNotes,
      SyncTable.dayEntryMergeEvents,
      SyncTable.profileTagRegistry,
    ]);
  });

  test('every storage pushable table appears in the descriptor exactly once',
      () {
    final rig = Rig();
    addTearDown(rig.dispose);

    final order = rig.engine.pushTableOrderForTest();
    final pushable = rig.storage.pushableTablesForTest;

    expect(order.toSet(), pushable,
        reason: 'the descriptor and the storage dirty-scan set must cover '
            'the same tables');
    expect(order, hasLength(pushable.length),
        reason: 'one descriptor entry per table — a duplicate would push (and '
            'encode) the same table twice');
  });
}
