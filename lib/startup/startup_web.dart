/// Web startup wiring for the database factory: unencrypted drift over
/// WASM/IndexedDB (browser storage is the platform's responsibility in v1).
library;

import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/web_db.dart';

Future<LunarLogDbFactory> buildDbFactory() async => webDbFactory();

/// Web has no database file to delete: the store lives in IndexedDB under
/// drift's control, so device reset (KTD16) runs
/// `LunarLogDatabase.wipeAllData()` there instead — it clears every table
/// including `sync_state`. Kept so the conditional export exposes one
/// `deleteLocalDatabase()` on every platform; a deliberate no-op here.
Future<void> deleteLocalDatabase() async {}
