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

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    httpClient: httpClient,
    authOptions: buildAuthClientOptions(isWeb: kIsWeb),
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

/// The Supabase auth client options for this platform (U4; KTD8; epic #831
/// slice 2).
///
/// PKCE only, never implicit: a hijacked custom-scheme code is useless
/// without the verifier in the same storage (KTD8). `detectSessionInUri` is
/// off on both platforms: `supabase_flutter` would otherwise exchange a code
/// during initialization, before anything can subscribe, and a cold-start
/// recovery event would be lost. `SupabaseAuthService` handles the callback
/// itself — natively from an app link, on web from the initial `Uri.base`.
///
/// Native passes [SecureLocalStorage] for both the session and the PKCE
/// verifier (Keychain/Keystore, KTD7). Web passes neither, so gotrue keeps
/// its own browser storage (`localStorage`) — which its own `signOut`
/// clears together with the session. Exposed for `web_auth_seam_test.dart`
/// rather than inlined into `Supabase.initialize`.
FlutterAuthClientOptions buildAuthClientOptions({
  required bool isWeb,
  SecureLocalStorage? nativeStorage,
}) {
  if (isWeb) {
    return const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: false,
    );
  }
  final storage = nativeStorage ?? SecureLocalStorage();
  return FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,
    detectSessionInUri: false,
    localStorage: storage,
    pkceAsyncStorage: storage,
  );
}
