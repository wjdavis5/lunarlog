/// Entry point (U7): the gate shell owns startup. The device-credential
/// gate runs before the database is opened on mobile (AE4 — a declined
/// credential never decrypts); any open/quarantine/key failure renders the
/// fail-closed screen (never a wipe).
///
/// Crash reporting (KTD12): `runWithSentry` initializes Sentry only when the
/// build carries a `SENTRY_DSN`; otherwise the app runner is called directly
/// and every Sentry call in the app is a no-op.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryHttpClient;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'app_lifecycle.dart';
import 'config.dart';
import 'data/gate/pin_credential_store.dart';
import 'data/privacy/ephemeral_files.dart';
import 'startup/gate/gate.dart';
import 'domain/sharing/invite_links.dart';
import 'data/notifications/notification_scheduler.dart';
import 'data/notifications/push_presentation.dart';
import 'data/sync/supabase_sync_transport.dart';
import 'data/sync/sync_transport.dart';
import 'domain/auth/auth_service.dart';
import 'domain/prediction/prediction_service.dart' show dateRolloverTicker;
import 'domain/util/timezone.dart';
import 'observability/sentry_bootstrap.dart';
import 'startup/startup.dart';
import 'startup/supabase_bootstrap.dart';

Future<void> main() => runWithSentry(appRunner: _runLunarlog);

/// `lunarlog://invite?code=...` (U8; R9) or its HTTPS universal-link twin
/// `https://<domain>/invite?code=...` (issue #129): the pairing deep link.
/// Anything else on the custom scheme belongs to the auth service's own
/// link observer and is ignored here. With no hosted domain configured
/// (`AppConfig.linkDomain` empty) only the custom-scheme form is honoured.
bool _isInviteLink(Uri? uri) =>
    isInviteLink(uri, linkDomain: AppConfig.linkDomain);

Future<void> _runLunarlog() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Issue #169: resolve current device timezone before UI is mounted so
  // DayEntry.tz and reminders plan against the actual device timezone.
  configurePlatformTimeZoneProvider(defaultLocalTimeZoneProvider);
  try {
    await resolveCurrentTimeZone();
  } catch (_) {}
  // Issue #843: best-effort sweep of the plugin cache copies (share_plus,
  // image_picker, file_picker) an export or a pick could have left behind if
  // the process was killed before its own cleanup ran. Fire-and-forget: the
  // sweep never throws and must never block or fail a launch.
  unawaited(sweepPluginCachesAtStartup());
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
  // Guardian invitations (U8; R9): the same app_links source the auth
  // service uses, filtered to the invite host. A cold-start code is
  // latched here and survives the sign-in gate.
  Stream<Uri>? inviteLinks;
  String? initialInviteCode;
  String? initialInviteProfileId;
  // U10: `kind=claim` marks a child-ownership-transfer link (routed to
  // ClaimProfileSheet downstream in app.dart, not here — `_isInviteLink`
  // stays kind-agnostic per KTD10).
  String? initialInviteKind;
  if (authService != null) {
    final appLinks = AppLinks();
    final initial = await appLinks.getInitialLink();
    if (_isInviteLink(initial)) {
      final invite = initial as Uri;
      initialInviteCode = invite.queryParameters['code'];
      initialInviteProfileId = invite.queryParameters['profile'];
      initialInviteKind = invite.queryParameters['kind'];
    }
    inviteLinks = appLinks.uriLinkStream.where(_isInviteLink);
  }
  // Issue #174: register the FCM background handler before runApp() so a
  // caregiver alert arriving while the app is backgrounded or terminated
  // is presented instead of dropped — firebase_messaging persists the
  // callback handles at registration time, which is why this must happen
  // early in every launch. Gated on [AppConfig.hasPush] like every
  // firebase_messaging touch (hasPush already excludes web): an
  // unconfigured build — every CI and fork build, with empty FCM defines —
  // never reaches the plugin. This registration is also what backs the
  // `remote-notification` UIBackgroundModes entry in
  // ios/Runner/Info.plist.
  if (AppConfig.hasPush) {
    FirebaseMessaging.onBackgroundMessage(pushBackgroundMessageHandler);
  }
  runApp(wrapWithSentry(LunarLogRoot(
    gate: defaultAppGate(),
    // #271: constructing the store does no I/O (it only opens secure
    // storage lazily, per call) — safe to pass unconditionally, including
    // on web, where the gate never consults it (`gate.requiresUnlock` is
    // false there, so `GateController.unlock` never reaches a PIN check).
    pinService: PinCredentialStore(),
    // Issue #244: `protectDatabaseFile` runs after `.open()` succeeds (so
    // the file is guaranteed to exist — `.open()`'s own `SELECT 1` probe
    // already forced drift to create it) and on every open, not just the
    // first — a device reset (KTD16) closes and recreates this file, which
    // needs the same iOS hardening reapplied. A no-op on Android/web.
    dbOpener: () async {
      final factory = await buildDbFactory();
      final db = await factory.open();
      // Issue #561: protect whichever file `factory` actually opened, not
      // whatever `localDatabaseFile()` would recompute — those differ when
      // relocation fell back to the legacy file.
      await protectDatabaseFile(factory.databasePath);
      return db;
    },
    // KTD7/KTD9: reminders are a native-only surface. The composition
    // factory builds the platform default (with its settings store) after
    // the database opens; web gets the no-op.
    buildDefaultScheduler: true,
    authService: authService,
    syncTransport: syncTransport,
    // U5/U6: with a client present the root also builds the sharing
    // service and the realtime coordinator next to the sync engine.
    supabaseClient: authService == null ? null : Supabase.instance.client,
    inviteLinks: inviteLinks,
    initialInviteCode: initialInviteCode,
    initialInviteProfileId: initialInviteProfileId,
    initialInviteKind: initialInviteKind,
    // Issue LLA-070: the real, periodic civil-date-rollover ticker — see
    // LunarLogRoot.dateTicker's own doc comment for why this is the only
    // construction site that passes it.
    dateTicker: dateRolloverTicker,
  )));
}
