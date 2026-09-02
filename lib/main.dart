/// Entry point (U7): the gate shell owns startup. The device-credential
/// gate runs before the database is opened on mobile (AE4 — a declined
/// credential never decrypts); any open/quarantine/key failure renders the
/// fail-closed screen (never a wipe).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_lifecycle.dart';
import 'data/gate/gate.dart';
import 'data/notifications/notification_scheduler.dart';
import 'startup/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LunarLogRoot(
    gate: defaultAppGate(),
    dbOpener: () async => (await buildDbFactory()).open(),
    // KTD7/KTD9: reminders are a native-only surface; web gets the no-op.
    scheduler:
        kIsWeb ? NoopReminderScheduler() : FlutterLocalNotificationsScheduler(),
  ));
}
