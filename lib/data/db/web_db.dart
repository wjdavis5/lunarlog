/// Web database wiring: unencrypted drift over WASM SQLite with IndexedDB
/// persistence.
///
/// Deliberately no key storage: this file does not import `key_store.dart`
/// or `flutter_secure_storage`, and the factory it builds has
/// `requireEncryption: false` — browser-local storage is the platform's
/// responsibility (v1 threat model).
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
    requireEncryption: false,
    // No keyStore, no preflight: web never touches key storage.
    plainExecutorBuilder: () async {
      final result = await WasmDatabase.open(
        databaseName: databaseName,
        sqlite3Uri: sqlite3Wasm,
        driftWorkerUri: driftWorker,
      );
      return result.resolvedExecutor;
    },
  );
}
