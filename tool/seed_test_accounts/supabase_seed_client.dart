/// HTTP client for the seeder: password sign-in, admin account bootstrap,
/// RPC calls under the user session, and RLS-scoped reads (issue #710).
///
/// The service key is confined to [adminFindUserByEmail],
/// [adminCreateUser], and [adminSetPassword] — the two bootstrap operations
/// the issue allows. Every data write goes through [rpc] with the signed-in
/// user's bearer token, exactly as the app does. No method ever returns or
/// logs a password or token.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'seed_config.dart';

/// A failure carrying the HTTP status and a redacted server message.
class SeedHttpException implements Exception {
  const SeedHttpException(this.status, this.message, this.context);

  final int status;

  /// The server's own message, safe to print (never contains credentials —
  /// this tool never sends any value it would need to redact back).
  final String message;

  /// Which operation failed ('sign-in', 'sync_push', ...).
  final String context;

  @override
  String toString() =>
      '[seed] $context failed (HTTP $status): $message';
}

/// The signed-in session for one fabricated account.
class SeedSession {
  const SeedSession({required this.accessToken, required this.userId});

  final String accessToken;
  final String userId;
}

/// A minimal admin-API user view.
class AdminUser {
  const AdminUser({required this.id, required this.hasPasswordIdentity});

  final String id;
  final bool hasPasswordIdentity;
}

class SupabaseSeedClient {
  SupabaseSeedClient({
    required this.config,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final SeedToolConfig config;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('${config.supabaseUrl}$path');

  Map<String, String> get _anonHeaders => {
        'apikey': config.publishableKey,
        'Content-Type': 'application/json',
      };

  http.Response _ok(http.Response res, String context) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SeedHttpException(
        res.statusCode,
        _serverMessage(res),
        context,
      );
    }
    return res;
  }

  String _serverMessage(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map &&
          decoded['msg'] is String) {
        return decoded['msg'] as String;
      }
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
      if (decoded is Map && decoded['error_description'] is String) {
        return decoded['error_description'] as String;
      }
    } catch (_) {
      // fall through to the raw body
    }
    final raw = utf8.decode(res.bodyBytes);
    return raw.length > 300 ? raw.substring(0, 300) : raw;
  }

  // ---------------------------------------------------------------------
  // Password auth (the only sign-in path this tool uses).
  // ---------------------------------------------------------------------

  Future<SeedSession> signInWithPassword(String email, String password) async {
    final res = await _http.post(
      _uri('/auth/v1/token?grant_type=password'),
      headers: _anonHeaders,
      body: jsonEncode({'email': email, 'password': password}),
    );
    _ok(res, 'sign-in for $email');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map ||
        body['access_token'] is! String ||
        (body['user'] as Map?)?['id'] is! String) {
      throw const SeedHttpException(0, 'unexpected sign-in response', 'sign-in');
    }
    return SeedSession(
      accessToken: body['access_token'] as String,
      userId: (body['user'] as Map)['id'] as String,
    );
  }

  // ---------------------------------------------------------------------
  // Admin bootstrap (service key; allowlist already verified by config).
  // ---------------------------------------------------------------------

  Future<AdminUser?> adminFindUserByEmail(String email) async {
    // GoTrue's admin list endpoint has no documented per-email filter, so
    // this paginates the (small, fabricated-only) user list and matches
    // client-side. Test accounts number in the single digits.
    const perPage = 1000;
    for (var page = 0; page < 50; page++) {
      final res = await _http.get(
        _uri('/auth/v1/admin/users?per_page=$perPage&page=$page'),
        headers: {
          'apikey': config.secretKey,
          'Authorization': 'Bearer ${config.secretKey}',
        },
      );
      _ok(res, 'admin user lookup');
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map || body['users'] is! List) {
        throw const SeedHttpException(
            0, 'unexpected admin user list response', 'admin user lookup');
      }
      final users = body['users'] as List;
      for (final user in users) {
        if (user is! Map) continue;
        final userEmail = user['email'];
        if (userEmail is String &&
            userEmail.toLowerCase() == email.toLowerCase()) {
          var hasPassword = false;
          final identities = user['identities'];
          if (identities is List) {
            for (final identity in identities) {
              if (identity is Map && identity['provider'] == 'email') {
                hasPassword = true;
              }
            }
          }
          return AdminUser(id: user['id'] as String, hasPasswordIdentity: hasPassword);
        }
      }
      if (users.length < perPage) return null;
    }
    return null;
  }

  Future<String> adminCreateUser(String email, String password) async {
    final res = await _http.post(
      _uri('/auth/v1/admin/users'),
      headers: {
        'apikey': config.secretKey,
        'Authorization': 'Bearer ${config.secretKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
      }),
    );
    _ok(res, 'admin create user for $email');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map || body['id'] is! String) {
      throw const SeedHttpException(
          0, 'unexpected admin create response', 'admin create user');
    }
    return body['id'] as String;
  }

  Future<void> adminSetPassword(String userId, String password) async {
    final res = await _http.put(
      _uri('/auth/v1/admin/users/$userId'),
      headers: {
        'apikey': config.secretKey,
        'Authorization': 'Bearer ${config.secretKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'password': password}),
    );
    _ok(res, 'admin set password');
  }

  /// Brings [account] to "exists and signs in with its password":
  /// creates it when missing, or adds a password identity when the account
  /// exists without one (e.g. an Apple-sign-in-only review account) — the
  /// additive bootstrap the issue allows. An account that already has a
  /// password identity which does not match is left untouched and fails
  /// loudly instead of being overwritten.
  Future<SeedSession> bootstrapAccount(SeedAccount account) async {
    try {
      return await signInWithPassword(account.email, account.password);
    } on SeedHttpException {
      // Not password-authable (yet) — fall through to the admin path.
    }
    final existing = await adminFindUserByEmail(account.email);
    if (existing == null) {
      await adminCreateUser(account.email, account.password);
    } else if (!existing.hasPasswordIdentity) {
      await adminSetPassword(existing.id, account.password);
    } else {
      throw SeedHttpException(
        401,
        'account already has a password identity that does not match the '
            'configured seed password; refusing to overwrite it — set '
            'LUNARLOG_SEED_PASSWORD_<SLUG> to the existing password or '
            'delete the fabricated account first',
        'bootstrap ${account.email}',
      );
    }
    return signInWithPassword(account.email, account.password);
  }

  // ---------------------------------------------------------------------
  // RPCs (user session).
  // ---------------------------------------------------------------------

  /// Calls an RPC under [session] and returns the decoded JSON body.
  Future<Object?> rpc(
    String name,
    Map<String, Object?> params,
    SeedSession session,
  ) async {
    final res = await _http.post(
      _uri('/rest/v1/rpc/$name'),
      headers: {
        'apikey': config.publishableKey,
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(params),
    );
    _ok(res, 'rpc $name');
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// RLS-scoped table read under [session] (guard/read-back checks).
  /// [queryString] is the full query string after `?` (e.g.
  /// `select=id&deleted_at=is.null`).
  Future<List<Map<String, Object?>>> restSelect(
    String table,
    String queryString,
    SeedSession session,
  ) async {
    final res = await _http.get(
      _uri('/rest/v1/$table?$queryString'),
      headers: {
        'apikey': config.publishableKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );
    _ok(res, 'select $table');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! List) {
      throw SeedHttpException(
          0, 'unexpected select response from $table', 'select $table');
    }
    return [
      for (final row in body)
        if (row is Map)
          row.map((k, v) => MapEntry(k.toString(), v as Object?)),
    ];
  }

  /// RLS-scoped count under [session], via PostgREST's `Prefer:
  /// count=exact` + a one-row range so the total arrives in the
  /// `Content-Range` header — immune both to the default 1000-row response
  /// cap a plain select hits and to the (config-gated) `count()` aggregate.
  /// [filterQueryString] carries only filters (no `select=`).
  Future<int> restCount(
    String table,
    String filterQueryString,
    SeedSession session,
  ) async {
    final query = 'select=id'
        '${filterQueryString.isEmpty ? '' : '&$filterQueryString'}';
    final res = await _http.get(
      _uri('/rest/v1/$table?$query'),
      headers: {
        'apikey': config.publishableKey,
        'Authorization': 'Bearer ${session.accessToken}',
        'Prefer': 'count=exact',
        'Range': '0-0',
      },
    );
    _ok(res, 'count $table');
    final contentRange = res.headers['content-range'];
    if (contentRange == null || !contentRange.contains('/')) {
      throw SeedHttpException(0, 'missing Content-Range from $table',
          'count $table');
    }
    final total = contentRange.split('/').last;
    final parsed = int.tryParse(total);
    if (parsed == null) {
      throw SeedHttpException(0, 'unparsable Content-Range "$total"',
          'count $table');
    }
    return parsed;
  }
}
