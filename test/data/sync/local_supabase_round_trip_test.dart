/// Issue #102's spike: the two halves of the sync contract — the Dart
/// row codec/transport and the SQL `sync_push` RPC — had never been
/// exercised together (the engine was tested only against
/// `FakeSyncTransport`, the RPC only against pgTAP). This file drives the
/// REAL `SupabaseSyncTransport` (which encodes through `row_codec.dart`
/// on the way out and decodes through it on the way back) against a REAL
/// local `supabase start` stack: a codec-encoded push goes through the
/// live `sync_push` RPC (validation, attribution stamping, RLS), and the
/// rows come back through a live RLS-scoped PostgREST select into a fresh
/// in-memory store via `LunarLogStorage.applyRemotePage`.
///
/// Boundary, documented honestly: this is the engine's transport + codec
/// + storage-apply seam, not the engine loop itself. `SupabaseSyncEngine`
/// orchestration (cycling, cursors, gating) stays covered by the fake
/// transport suite; what only this test can catch is a drift between the
/// codec's JSON shape and the SQL the migrations define — the seam where
/// each half's tests were green while the pair had never met.
///
/// Runs ONLY when a local Supabase stack is reachable (skips otherwise,
/// so `flutter test` on a plain checkout and the sharded CI matrix stay
/// green): `npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,
/// mailpit,studio,edge-runtime,logflare,vector,supavisor` per AGENTS.md's
/// Migration Flow, then `flutter test
/// test/data/sync/local_supabase_round_trip_test.dart`. CI runs it in the
/// `db-tests` job, which already boots exactly that stack for pgTAP.
///
/// The default keys below are the universal local-development JWTs every
/// `supabase start` project issues (`iss: supabase-demo` — not secrets;
/// see the values `supabase status -o env` prints as ANON_KEY /
/// SERVICE_ROLE_KEY). A stack provisioned with a custom JWT secret can
/// override them via `LUNARLOG_LOCAL_SUPABASE_PUBLISHABLE_KEY` /
/// `LUNARLOG_LOCAL_SUPABASE_SERVICE_ROLE_KEY`. The service-role key is
/// used for exactly one call — creating an email-confirmed test user,
/// since the local stack's `enable_confirmations = true` plus no mailpit
/// means a plain `signUp` can never yield a session — after which every
/// request runs as that ordinary authenticated user.
library;

import 'dart:io' show Platform;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/row_codec.dart';
import 'package:lunarlog/data/sync/supabase_sync_transport.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AdminUserAttributes, SupabaseClient;

/// The stock local-dev anon JWT (role `anon`, issuer `supabase-demo`).
const String _kLocalDevAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

/// The stock local-dev service-role JWT — same issuer, role
/// `service_role`. Local development only; never a production secret.
const String _kLocalDevServiceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

class _FixedClock {
  _FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// Whether the local stack's PostgREST root answers with the publishable
/// key — the cheap probe that decides skip-vs-run before any test is
/// registered.
Future<bool> _stackReachable(String url, String publishableKey) async {
  try {
    final response = await http
        .get(
          Uri.parse('$url/rest/v1/'),
          headers: {'apikey': publishableKey},
        )
        .timeout(const Duration(seconds: 2));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<void> main() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final url = Platform.environment['LUNARLOG_LOCAL_SUPABASE_URL'] ??
      'http://127.0.0.1:54321';
  final publishableKey =
      Platform.environment['LUNARLOG_LOCAL_SUPABASE_PUBLISHABLE_KEY'] ??
          _kLocalDevAnonKey;
  final serviceRoleKey =
      Platform.environment['LUNARLOG_LOCAL_SUPABASE_SERVICE_ROLE_KEY'] ??
          _kLocalDevServiceRoleKey;

  // Decided up front (an async probe before registration) so the skip is a
  // real, visible skip — never a silent pass.
  final reachable = await _stackReachable(url, publishableKey);
  final skip = reachable
      ? null
      : 'no local Supabase stack reachable at $url — issue #102 round '
          'trip; start one with the AGENTS.md Migration Flow command '
          '(`npx supabase@2.116.0 start -x realtime,storage-api,imgproxy,'
          'mailpit,studio,edge-runtime,logflare,vector,supavisor`)';

  test(
    'issue #102: codec-encoded rows round-trip through the live local '
    'sync_push RPC and back into a fresh store via applyRemotePage',
    () async {
      final email =
          'issue-102-${DateTime.now().microsecondsSinceEpoch}@roundtrip.local';
      const password = 'LocalRoundTrip#102x';

      final admin = SupabaseClient(url, serviceRoleKey);
      final user = SupabaseClient(url, publishableKey);
      addTearDown(() async {
        await user.dispose();
        await admin.dispose();
      });

      await admin.auth.admin.createUser(AdminUserAttributes(
        email: email,
        password: password,
        emailConfirm: true,
      ));
      final auth = await user.auth.signInWithPassword(
        email: email,
        password: password,
      );
      expect(auth.session, isNotNull,
          reason: 'the admin-created confirmed user must be able to sign '
              'in — without a session every later call runs as anon and '
              'the RPC correctly refuses it');
      final uid = auth.session!.user.id;

      // "Device A": a local store whose dirty rows are encoded by the
      // real codec, exactly as the engine's push path would.
      final clockA = _FixedClock(DateTime.utc(2026, 9, 14, 9));
      final dbA = LunarLogDatabase(NativeDatabase.memory());
      final storeA = LunarLogStorage(dbA, clock: clockA.call);
      addTearDown(dbA.close);
      final created =
          await storeA.upsertProfile(displayName: 'Round Trip', isMinor: false);
      final entry1 = await storeA.upsertDayEntry(
        profileId: created.id,
        localDate: '2026-09-10',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['cramps'],
        note: 'first',
      );
      final entry2 = await storeA.upsertDayEntry(
        profileId: created.id,
        localDate: '2026-09-11',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      final profileA = (await storeA.getProfiles(includeTombstones: true))
          .firstWhere((p) => p.id == created.id);

      final transport = SupabaseSyncTransport(user);
      final pushed = await transport.push(PushBatch(
        profiles: [encodeProfile(profileA)],
        dayEntries: [
          encodeDayEntry(entry1),
          encodeDayEntry(entry2),
        ],
      ));
      expect(pushed.rejectedIds, isEmpty,
          reason: 'the real RPC accepted every codec-encoded row — a '
              'codec/RPC shape drift lands here as a rejection or a '
              'PostgrestException');
      expect(pushed.resolved, isEmpty);
      expect(pushed.serverNow.toUtc().isAfter(DateTime.utc(2026, 1, 1)),
          isTrue);

      expect(await transport.fetchMaxVersion(SyncTable.profiles),
          greaterThan(0),
          reason: 'the pushed profile is visible to its owner through RLS');
      final watermark = await transport.fetchWatermark();
      expect(watermark, isNotNull);
      expect(watermark!, greaterThan(0));

      // "Device B": a fresh store that has never seen any of this — the
      // pull page goes through the live RLS-scoped select, decodes via
      // the codec, and lands through the same applyRemotePage the engine
      // uses per page.
      final dbB = LunarLogDatabase(NativeDatabase.memory());
      final storeB = LunarLogStorage(dbB, clock: clockA.call);
      addTearDown(dbB.close);
      final profilePage = await transport.pullPage(
          table: SyncTable.profiles, afterVersion: 0, limit: 500);
      expect(profilePage, hasLength(1),
          reason: 'RLS shows this user exactly its own profile');
      final entryPage = await transport.pullPage(
          table: SyncTable.dayEntries, afterVersion: 0, limit: 500);
      expect(entryPage, hasLength(2));
      await storeB.applyRemotePage(
          table: SyncTable.profiles, rows: profilePage, newCursor: 1);
      await storeB.applyRemotePage(
          table: SyncTable.dayEntries, rows: entryPage, newCursor: 2);

      final profileB = (await storeB.getProfiles()).single;
      expect(profileB.displayName, 'Round Trip');
      expect(profileB.dirty, isFalse);
      final entriesB =
          await storeB.getDayEntries(profileId: profileB.id, includeTombstones: true);
      expect(entriesB, hasLength(2));
      final pulled1 =
          entriesB.firstWhere((e) => e.localDate == '2026-09-10');
      expect(pulled1.flow, FlowLevel.medium);
      expect(pulled1.tags, ['cramps']);
      expect(pulled1.note, 'first');
      expect(pulled1.updatedAt, entry1.updatedAt,
          reason: 'the LWW timestamp crossed the wire unchanged');
      expect(pulled1.loggedByUserId, uid,
          reason: 'the real RPC stamped attribution from the JWT — a '
              'codec/SQL column-name drift lands here as null or a decode '
              'error');
      expect(pulled1.dirty, isFalse);

      // A stale second push of entry1 (older updated_at at the wire
      // boundary): the real RPC must decline it and answer with its
      // stored copy — the resolved-row decode path against live JSON.
      final staleJson = Map<String, Object?>.of(encodeDayEntry(entry1))
        ..['updated_at'] =
            encodeTimestamp(entry1.updatedAt.subtract(const Duration(hours: 2)));
      final declined = await transport.push(
        PushBatch(dayEntries: [staleJson]),
      );
      expect(declined.rejectedIds, isEmpty);
      expect(declined.resolved, hasLength(1),
          reason: 'the older row loses LWW and is resolved back');
      final resolved = declined.resolved.single;
      expect(resolved, isA<RemoteDayEntryRow>());
      final resolvedEntry = resolved as RemoteDayEntryRow;
      expect(resolvedEntry.id, entry1.id);
      expect(resolvedEntry.updatedAt, entry1.updatedAt,
          reason: 'the resolution carries the server\'s stored (newer) '
              'copy, so a device applying it converges instead of '
              'reverting');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
