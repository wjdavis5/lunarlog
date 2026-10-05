/// Placeholder for any platform that is not native.
library;

import 'package:lunarlog/data/db/db_factory.dart';

Future<LunarLogDbFactory> buildDbFactory() async =>
    throw UnsupportedError('lunarlog does not support this platform');

Future<void> deleteLocalDatabase() async =>
    throw UnsupportedError('lunarlog does not support this platform');

Future<void> protectDatabaseFile(String databasePath) async =>
    throw UnsupportedError('lunarlog does not support this platform');
