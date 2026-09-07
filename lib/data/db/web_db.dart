/// Web database wiring: drift over WASM SQLite with IndexedDB persistence.
///
/// `WasmDatabase.open` picks the best storage the current browser offers.
/// Without COOP/COEP headers it falls back to IndexedDB-backed modes
/// (sharedIndexedDb / unsafeIndexedDb), so no special server headers are
/// required. `web/sqlite3.wasm` and `web/drift_worker.js` are the
/// version-matched assets from the drift-2.34.3 GitHub release.
library;

import 'package:drift/wasm.dart';

import 'db_factory.dart';

LunarLogDbFactory webDbFactory({
  String databaseName = 'lunarlog',
  Uri? sqlite3WasmUri,
  Uri? driftWorkerUri,
}) {
  final sqlite3Wasm = sqlite3WasmUri ?? Uri.parse('sqlite3.wasm');
  final driftWorker = driftWorkerUri ?? Uri.parse('drift_worker.js');
  return LunarLogDbFactory(
    databasePath: 'web:$databaseName',
    executorBuilder: () async {
      final result = await WasmDatabase.open(
        databaseName: databaseName,
        sqlite3Uri: sqlite3Wasm,
        driftWorkerUri: driftWorker,
      );
      return result.resolvedExecutor;
    },
  );
}
