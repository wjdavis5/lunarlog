/// Entry point: open the database via U2's platform factory, then hand off
/// to the app. Fail-closed startup: any open/quarantine/key error renders
/// the basic startup error screen instead of a silent crash.
library;

import 'package:flutter/material.dart';

import 'app.dart';
import 'startup/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final factory = await buildDbFactory();
    final db = await factory.open();
    runApp(LunarLogApp(db: db));
  } catch (error, stackTrace) {
    debugPrint('lunarlog startup failed: $error\n$stackTrace');
    runApp(StartupErrorApp(error: error));
  }
}
