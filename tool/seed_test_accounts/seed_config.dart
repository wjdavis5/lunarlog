/// Environment/config parsing for the test-account seeder (issue #710).
///
/// Every credential is read from the environment (the repo-root `.env` is
/// the operator convention — `main.dart` loads it and merges it under the
/// real environment). Nothing here ever prints a secret value; errors name
/// the missing/wrong *key*, never the value.
///
/// The allowlist check is the tool's first and hardest safety gate
/// (AC #2): [buildSeedToolConfig] throws before the caller has built any
/// HTTP client when `LUNARLOG_SEED_ACCOUNT_EMAIL` or
/// `LUNARLOG_SEED_PARTNER_EMAIL` is not a member of
/// `LUNARLOG_SEED_ALLOWLIST` — so a non-allowlisted target can never reach
/// even the read-only admin lookup, let alone a write.
library;

/// Thrown for every configuration problem; [message] is safe to print.
class SeedConfigException implements Exception {
  const SeedConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One fabricated test account the tool may operate on.
class SeedAccount {
  const SeedAccount({required this.email, required this.password});

  final String email;

  /// The fabricated shared password (per-account override when
  /// `LUNARLOG_SEED_PASSWORD_<SLUG>` is set). Never printed.
  final String password;
}

/// Fully validated tool configuration.
class SeedToolConfig {
  const SeedToolConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    required this.secretKey,
    required this.target,
    required this.partner,
    required this.allowlist,
  });

  /// Project URL. `http://127.0.0.1:54321` selects the local dev stack.
  final String supabaseUrl;

  /// The publishable (anon) key; authenticates REST calls alongside the
  /// user bearer token.
  final String publishableKey;

  /// The service-role key. Used ONLY for (a) creating a missing account and
  /// (b) adding a password identity to an existing allowlisted account that
  /// has none — never for any data write (all data flows through
  /// `sync_push` under the user's own session).
  final String secretKey;

  final SeedAccount target;
  final SeedAccount partner;

  /// The allowlisted emails (trimmed, lower-cased).
  final List<String> allowlist;
}

/// The demo keys the local Supabase stack (`supabase start`) issues. They
/// are public by construction (printed by `supabase status` on every local
/// run, derived from the fixed local JWT secret) and are used only when
/// `SUPABASE_URL` points at localhost and no explicit key was provided, so
/// the local-validation flow needs no copy-paste step. (The stack also
/// mints per-install `sb_publishable_...`/`sb_secret_...` keys; the fixed
/// JWT-style pair below is equivalent for local use and stable across
/// machines.) For any non-local URL the real keys are required from the
/// environment.
const String kLocalDemoPublishableKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.'
    'CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const String kLocalDemoServiceKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.'
    'EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

/// Uppercased env-slug for an email: every character outside [A-Za-z0-9]
/// becomes `_` (e.g. `seed.e2e.local@example.com` ->
/// `SEED_E2E_LOCAL_EXAMPLE_COM`), matching the per-account password-override
/// key `LUNARLOG_SEED_PASSWORD_<SLUG>` from the issue.
String passwordEnvSlug(String email) {
  final upper = email.toUpperCase();
  final buffer = StringBuffer();
  for (final code in upper.codeUnits) {
    final isAlnum = (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A);
    buffer.writeCharCode(isAlnum ? code : 0x5F);
  }
  return buffer.toString();
}

/// Resolves the password for [email]: the per-account override
/// `LUNARLOG_SEED_PASSWORD_<SLUG>` when set, else the shared
/// `LUNARLOG_SEED_PASSWORD`. Empty string when neither is set.
String resolvePassword(String email, Map<String, String> env) {
  final override = env['LUNARLOG_SEED_PASSWORD_${passwordEnvSlug(email)}'];
  if (override != null && override.trim().isNotEmpty) {
    return override.trim();
  }
  return (env['LUNARLOG_SEED_PASSWORD'] ?? '').trim();
}

/// Whether [host] is the local dev stack (either loopback name).
bool _isLocalHost(Uri url) {
  final host = url.host.toLowerCase();
  return host == '127.0.0.1' || host == 'localhost' || host == '::1';
}

/// Parses and validates the allowlist value (comma-separated emails).
List<String> parseAllowlist(String raw) => [
        for (final entry in raw.split(','))
          if (entry.trim().isNotEmpty) entry.trim().toLowerCase(),
      ];

/// Builds the fully validated config or throws [SeedConfigException].
/// Pure: performs no I/O, so it can run before any network client exists
/// (the "refuse before any write" guarantee).
SeedToolConfig buildSeedToolConfig(Map<String, String> env) {
  final rawUrl = (env['SUPABASE_URL'] ?? '').trim();
  if (rawUrl.isEmpty) {
    throw const SeedConfigException(
      'SUPABASE_URL is not set. For local validation use '
      'http://127.0.0.1:54321 (see docs/ops/seed-test-account.md).',
    );
  }
  final Uri url;
  try {
    url = Uri.parse(rawUrl);
  } on FormatException {
    throw SeedConfigException('SUPABASE_URL is not a valid URL: $rawUrl');
  }
  final local = _isLocalHost(url);

  final allowlistRaw = env['LUNARLOG_SEED_ALLOWLIST'] ?? '';
  final allowlist = parseAllowlist(allowlistRaw);
  if (allowlist.isEmpty) {
    throw const SeedConfigException(
      'LUNARLOG_SEED_ALLOWLIST is not set or empty. The seeder refuses to '
      'run without an explicit allowlist of fabricated test-account emails.',
    );
  }

  String requireAllowlisted(String keyName) {
    final email = (env[keyName] ?? '').trim().toLowerCase();
    if (email.isEmpty) {
      throw SeedConfigException('$keyName is not set.');
    }
    if (!allowlist.contains(email)) {
      // AC #2: refuse before any write — including the account lookup this
      // tool would otherwise perform next. Never a warning-and-continue.
      throw SeedConfigException(
        '$keyName ($email) is not in LUNARLOG_SEED_ALLOWLIST. Refusing to '
        'run — add the fabricated test account to the allowlist first.',
      );
    }
    return email;
  }

  final targetEmail = requireAllowlisted('LUNARLOG_SEED_ACCOUNT_EMAIL');
  final partnerEmail = requireAllowlisted('LUNARLOG_SEED_PARTNER_EMAIL');
  if (targetEmail == partnerEmail) {
    throw const SeedConfigException(
      'LUNARLOG_SEED_PARTNER_EMAIL must differ from '
      'LUNARLOG_SEED_ACCOUNT_EMAIL (the sharing partner is a second '
      'fabricated account).',
    );
  }

  final targetPassword = resolvePassword(targetEmail, env);
  final partnerPassword = resolvePassword(partnerEmail, env);
  if (targetPassword.isEmpty || partnerPassword.isEmpty) {
    throw const SeedConfigException(
      'LUNARLOG_SEED_PASSWORD (or a LUNARLOG_SEED_PASSWORD_<SLUG> override '
      'for each account) is not set.',
    );
  }

  var publishable = (env['SUPABASE_PUBLISHABLE_KEY'] ?? '').trim();
  var secret = (env['SUPABASE_SECRET_KEY'] ?? '').trim();
  if (local) {
    if (publishable.isEmpty) publishable = kLocalDemoPublishableKey;
    if (secret.isEmpty) secret = kLocalDemoServiceKey;
  } else {
    if (publishable.isEmpty) {
      throw const SeedConfigException(
        'SUPABASE_PUBLISHABLE_KEY is not set (required for a non-local '
        'SUPABASE_URL).',
      );
    }
    if (secret.isEmpty) {
      throw const SeedConfigException(
        'SUPABASE_SECRET_KEY is not set (required for a non-local '
        'SUPABASE_URL — it is used only for account bootstrap).',
      );
    }
  }

  return SeedToolConfig(
    supabaseUrl: rawUrl.replaceAll(RegExp(r'/+$'), ''),
    publishableKey: publishable,
    secretKey: secret,
    target: SeedAccount(email: targetEmail, password: targetPassword),
    partner: SeedAccount(email: partnerEmail, password: partnerPassword),
    allowlist: allowlist,
  );
}
