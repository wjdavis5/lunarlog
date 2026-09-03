/// Entry point (U7): the gate shell owns startup. The device-credential
/// gate runs before the database is opened on mobile (AE4 — a declined
/// credential never decrypts); any open/quarantine/key failure renders the
/// fail-closed screen (never a wipe).
///
/// Crash reporting (KTD12): `runWithSentry` initializes Sentry only when the
/// build carries a `SENTRY_DSN`; otherwise the app runner is called directly
/// and every Sentry call in the app is a no-op.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryHttpClient;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'app_lifecycle.dart';
import 'config.dart';
import 'data/gate/gate.dart';
import 'data/notifications/notification_scheduler.dart';
import 'data/sync/supabase_sync_transport.dart';
import 'data/sync/sync_transport.dart';
import 'domain/auth/auth_service.dart';
import 'observability/sentry_bootstrap.dart';
import 'startup/startup.dart';
import 'startup/supabase_bootstrap.dart';

Future<void> main() => runWithSentry(appRunner: _runLunarlog);

Future<void> _runLunarlog() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Supabase auth (U4): initialized before the first frame so a cold-start
  // recovery link is latched in the service before any widget exists
  // (KTD8). Null when the build has no Supabase configuration (KTD11).
  // A bootstrap failure must never keep the local app from starting (R10).
  // With Sentry active, Supabase's HTTP goes through `SentryHttpClient` so
  // failed requests are captured (scrubbed to path + method by `scrubEvent`).
  AuthService? authService;
  try {
    authService = await bootstrapSupabase(
      httpClient: AppConfig.hasSentry ? SentryHttpClient() : null,
    );
  } catch (error) {
    debugPrint('lunarlog: supabase bootstrap failed (${error.runtimeType})');
  }
  // Cloud sync (U5/U10): the transport exists only when the bootstrap
  // produced a service (`AppConfig.hasSupabase` and initialization
  // succeeded); `LunarLogRoot` builds the engine after the database opens
  // and only when both collaborators are present (KTD11).
  final SyncTransport? syncTransport = authService == null
      ? null
      : SupabaseSyncTransport(Supabase.instance.client);
  runApp(wrapWithSentry(LunarLogRoot(
    gate: defaultAppGate(),
    dbOpener: () async => (await buildDbFactory()).open(),
    // KTD7/KTD9: reminders are a native-only surface; web gets the no-op.
    scheduler:
        kIsWeb ? NoopReminderScheduler() : FlutterLocalNotificationsScheduler(),
    authService: authService,
    syncTransport: syncTransport,
  )));
}
