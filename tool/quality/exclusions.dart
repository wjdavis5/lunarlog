/// The reviewed coverage/CRAP exclusion list (plan U1, KTD4).
///
/// Both gates (`coverage_gate.dart`, `crap_gate.dart`) read the same filtered
/// lcov produced by [filteredCoverageFromFile] in `coverage_filter.dart`, so
/// a file excluded here is out of the denominator for both — one list, read
/// once (KTD6).
///
/// Each entry is whole-file (lcov's `SF:` records are the only unit this
/// operates on); a file that mixes real platform-adapter code with
/// meaningfully testable pure logic still gets that logic tested directly —
/// exclusion only removes the file from the *gate's* denominator, it doesn't
/// stop the file from being tested. See the plan's KTD4 for the review
/// behind each entry.
///
/// [excludedLibFilePaths] is the single canonical list — literal,
/// repo-relative paths reviewed one by one — that [coveragePatterns]
/// compiles into `RegExp`s and `tool/mutation_gate.dart` reads directly for
/// its generated `mutation_test` rules document, so the two never drift.
/// Generated code (`**/*.g.dart`) is handled separately since it's a suffix
/// glob, not a literal path.
library;

import 'dart:io';

/// One reviewed exclusion: a literal, repo-relative file path plus why it's
/// here.
class CoverageExclusion {
  const CoverageExclusion(this.path, this.reason);

  final String path;
  final String reason;
}

final List<CoverageExclusion> excludedLibFilePaths = [
  const CoverageExclusion(
    'lib/data/auth/google_sign_in_client.dart',
    'PluginGoogleSignInClient wraps the google_sign_in plugin and cannot '
        'run under flutter test; the file also holds a trivial immutable '
        'value type with no branching.',
  ),
  const CoverageExclusion(
    'lib/data/auth/auth_gateway.dart',
    'GoTrueAuthGateway and AppLinksSource are 100% platform adapters over '
        'GoTrueClient/app_links; the file also declares two interfaces '
        '(AuthGateway, AuthLinkSource) that contribute no executable lines, '
        'so nothing testable is lost by excluding the whole file.',
  ),
  const CoverageExclusion(
    'lib/data/db/key_store.dart',
    'SecureDbKeyStore wraps flutter_secure_storage and cannot run under '
        'flutter test. isValidDbKeyHex and generateKey() are pure and get '
        'direct unit tests anyway — exclusion only removes this file from '
        'the gate denominator, not from the test suite.',
  ),
  const CoverageExclusion(
    'lib/data/notifications/notification_scheduler.dart',
    'FlutterLocalNotificationsScheduler wraps flutter_local_notifications '
        'and cannot run under flutter test. NoopReminderScheduler is pure '
        'and gets a direct unit test anyway, same treatment as key_store.dart.',
  ),
  const CoverageExclusion(
    'lib/data/export/account_export_writer.dart',
    'AccountExportWriter wraps path_provider (temp directory) and '
        'share_plus (the platform share sheet), neither of which can run '
        'under flutter test. All content-shaped logic lives in the pure '
        'lib/domain/export/account_export.dart builder it wraps, which is '
        'unit-tested directly; this file is proven by the U7 device '
        'checklist instead, same treatment as google_sign_in_client.dart.',
  ),
];

final RegExp _generatedCodePattern = RegExp(r'\.g\.dart$');

/// [excludedLibFilePaths] compiled to anchored, escaped `RegExp`s, plus the
/// generated-code glob — the matcher [isExcluded] actually uses.
final List<RegExp> coveragePatterns = [
  _generatedCodePattern,
  for (final e in excludedLibFilePaths) RegExp('${RegExp.escape(e.path)}\$'),
];

/// lcov `SF:` paths from `flutter test --coverage` are OS-native
/// (backslashes on Windows); exclusion patterns are written with forward
/// slashes, so normalize before matching.
String normalizeSourcePath(String sourceFilePath) =>
    sourceFilePath.replaceAll('\\', '/');

bool isExcluded(String sourceFilePath) {
  final normalized = normalizeSourcePath(sourceFilePath);
  return coveragePatterns.any((p) => p.hasMatch(normalized));
}

/// One non-excluded `lib/` Dart file: the real [File] to read, paired with
/// its `lib/...`-rooted, forward-slash path (computed once here, not
/// recomputed by each caller).
class LibDartFile {
  const LibDartFile(this.file, this.libRelativePath);

  final File file;
  final String libRelativePath;
}

/// Every non-excluded `.dart` file under [libDir] ("lib" by default),
/// sorted by path for a stable, readable order. Shared by
/// `crap_gate.dart` and `mutation_gate.dart` so the walk-and-filter logic
/// (and its exclusion behavior) lives in exactly one place.
List<LibDartFile> nonExcludedLibDartFiles([Directory? libDir]) {
  final dir = libDir ?? Directory('lib');
  final result = <LibDartFile>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relative = normalizeSourcePath(
      entity.path.replaceFirst('${dir.path}${Platform.pathSeparator}', ''),
    );
    final libRelativePath = 'lib/$relative';
    if (!isExcluded(libRelativePath)) {
      result.add(LibDartFile(entity, libRelativePath));
    }
  }
  result.sort((a, b) => a.libRelativePath.compareTo(b.libRelativePath));
  return result;
}
