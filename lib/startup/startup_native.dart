/// Native (mobile/desktop) startup wiring for the database factory: file in
/// the app documents directory, key via flutter_secure_storage, encrypted
/// open enforced by U2's factory (fail-closed).
library;

import 'dart:io';

import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/key_store.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:path_provider/path_provider.dart';

Future<LunarLogDbFactory> buildDbFactory() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(
      '${dir.path}${Platform.pathSeparator}lunarlog.db');
  return nativeDbFactory(file: file, keyStore: SecureDbKeyStore());
}
