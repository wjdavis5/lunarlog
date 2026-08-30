/// Web startup wiring for the database factory: unencrypted drift over
/// WASM/IndexedDB (browser storage is the platform's responsibility in v1).
library;

import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/web_db.dart';

Future<LunarLogDbFactory> buildDbFactory() async => webDbFactory();
