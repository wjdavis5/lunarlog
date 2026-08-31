/// Entry point (U7): the gate shell owns startup. The device-credential
/// gate runs before the database is opened on mobile (AE4 — a declined
/// credential never decrypts); any open/quarantine/key failure renders the
/// fail-closed screen (never a wipe).
library;

import 'package:flutter/material.dart';

import 'app_lifecycle.dart';
import 'data/gate/gate.dart';
import 'startup/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LunarLogRoot(
    gate: defaultAppGate(),
    dbOpener: () async => (await buildDbFactory()).open(),
  ));
}
