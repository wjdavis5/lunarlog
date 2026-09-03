/// Supabase bootstrap (U4; KTD7, KTD8, KTD11): the one place that calls
/// `Supabase.initialize`, run from `main()` before `runApp`. Returns the
/// started [AuthService], or `null` when the build carries no Supabase
/// configuration (`AppConfig.hasSupabase` is a compile-time constant, so
/// an unconfigured build tree-shakes the rest).
///
/// [httpClient] is the seam for U7's `SentryHttpClient`.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:lunarlog/config.dart';
import 'package:lunarlog/data/auth/auth_gateway.dart';
import 'package:lunarlog/data/auth/secure_local_storage.dart';
import 'package:lunarlog/data/auth/supabase_auth_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<AuthService?> bootstrapSupabase({http.Client? httpClient}) async {
  if (!AppConfig.hasSupabase) return null;

  // PKCE only (never implicit: a hijacked custom-scheme code is useless
  // without the verifier in this app's secure storage, KTD8).
  // detectSessionInUri is off: supabase_flutter would exchange the code
  // during initialization, before anything can subscribe, and a cold-start
  // recovery event would be lost. SupabaseAuthService handles links.
  final authOptions = kIsWeb
      ? const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUri: false,
        )
      : FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUri: false,
          localStorage: SecureLocalStorage(),
          pkceAsyncStorage: SecureLocalStorage(),
        );

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    httpClient: httpClient,
    authOptions: authOptions,
    // Every PostgREST call (the `sync_push` RPC and the pull selects) gets
    // a per-attempt timeout, so a stalled connection cannot hang a sync
    // cycle forever. The resulting `TimeoutException` is mapped by
    // `mapSyncTransportError` to `SyncTransportError.network()`, which the
    // engine retries with backoff.
    postgrestOptions: const PostgrestClientOptions(
      requestTimeout: Duration(seconds: 20),
    ),
  );

  final service = SupabaseAuthService(
    gateway: GoTrueAuthGateway(Supabase.instance.client.auth),
    links: AppLinksSource(),
  );
  await service.start();
  return service;
}
