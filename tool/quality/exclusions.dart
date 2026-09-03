/// The reviewed coverage/CRAP exclusion list (plan U1, KTD4).
///
/// Both gates (`coverage_gate.dart`, `crap_gate.dart`) read the same filtered
/// lcov produced by [filterLcov] in `coverage_filter.dart`, so a file
/// excluded here is out of the denominator for both — one list, read once
/// (KTD6).
///
/// Each pattern is whole-file (lcov's `SF:` records are the only unit this
/// operates on); a file that mixes real platform-adapter code with
/// meaningfully testable pure logic still gets that logic tested directly —
/// exclusion only removes the file from the *gate's* denominator, it doesn't
/// stop the file from being tested. See the plan's KTD4 for the review
/// behind each entry.
library;

/// One reviewed exclusion: the pattern plus why it's here.
class CoverageExclusion {
  const CoverageExclusion(this.pattern, this.reason);

  /// Matched against the lcov `SF:` path (forward-slash normalized — see
  /// [normalizeSourcePath]).
  final RegExp pattern;

  final String reason;
}

final List<CoverageExclusion> coverageExclusions = [
  CoverageExclusion(
    RegExp(r'\.g\.dart$'),
    'Generated code (build_runner/drift) — not hand-written, not reviewed '
        'line-by-line.',
  ),
  CoverageExclusion(
    RegExp(r'lib/data/auth/google_sign_in_client\.dart$'),
    'PluginGoogleSignInClient wraps the google_sign_in plugin and cannot '
        'run under flutter test; the file also holds a trivial immutable '
        'value type with no branching.',
  ),
  CoverageExclusion(
    RegExp(r'lib/data/auth/auth_gateway\.dart$'),
    'GoTrueAuthGateway and AppLinksSource are 100% platform adapters over '
        'GoTrueClient/app_links; the file also declares two interfaces '
        '(AuthGateway, AuthLinkSource) that contribute no executable lines, '
        'so nothing testable is lost by excluding the whole file.',
  ),
  CoverageExclusion(
    RegExp(r'lib/data/db/key_store\.dart$'),
    'SecureDbKeyStore wraps flutter_secure_storage and cannot run under '
        'flutter test. isValidDbKeyHex and generateKey() are pure and get '
        'direct unit tests anyway — exclusion only removes this file from '
        'the gate denominator, not from the test suite.',
  ),
  CoverageExclusion(
    RegExp(r'lib/data/notifications/notification_scheduler\.dart$'),
    'FlutterLocalNotificationsScheduler wraps flutter_local_notifications '
        'and cannot run under flutter test. NoopReminderScheduler is pure '
        'and gets a direct unit test anyway, same treatment as key_store.dart.',
  ),
];

/// lcov `SF:` paths from `flutter test --coverage` are OS-native
/// (backslashes on Windows); exclusion patterns are written with forward
/// slashes, so normalize before matching.
String normalizeSourcePath(String sourceFilePath) =>
    sourceFilePath.replaceAll('\\', '/');

bool isExcluded(String sourceFilePath) {
  final normalized = normalizeSourcePath(sourceFilePath);
  return coverageExclusions.any((e) => e.pattern.hasMatch(normalized));
}
