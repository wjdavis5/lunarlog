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
    'lib/startup/startup_native.dart',
    'protectDatabaseFile (issue #244) is an iOS-only platform-channel call '
        '(NSFileProtectionComplete/NSURLIsExcludedFromBackupKey via '
        'AppDelegate.swift) gated on defaultTargetPlatform == '
        'TargetPlatform.iOS, which flutter test never reports on this '
        'suite\'s host platforms — the branch cannot be driven true, so the '
        'method scores 0% covered no matter how it is called, same '
        'treatment as google_sign_in_client.dart. localDatabaseFile, '
        '_legacyDatabaseFile, buildDbFactory, and deleteLocalDatabase are '
        'thin path_provider wrappers with no branching logic worth testing '
        'in isolation, same treatment. Round 2 (review) moved every piece '
        'of pure, testable relocation logic — relocateLegacyDatabase and '
        'its helpers, the copier seam, staged-copy verification, '
        'deleteDatabaseFiles, deleteRelocationArtifacts, and the sentinel '
        'handling — out of this file into '
        'lib/startup/database_relocation.dart, which is NOT excluded and '
        'is directly, fully unit-tested against real temp-directory files '
        'in test/startup/database_relocation_test.dart; this file keeps '
        'only the path_provider-dependent wrappers and the iOS-only '
        'channel call, so excluding it no longer hides any testable logic '
        'from the gate\'s denominator.',
  ),
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
    'lib/data/notifications/notification_scheduler.dart',
    'FlutterLocalNotificationsScheduler wraps flutter_local_notifications '
        'and cannot run under flutter test. NoopReminderScheduler is pure '
        'and gets a direct unit test anyway, same treatment as '
        'google_sign_in_client.dart.',
  ),
  // Issue #207: image_picker_attachment_source.dart is deliberately NOT
  // listed here any more. It still wraps the image_picker plugin, but every
  // decision around the plugin call (downscale/normalisation parameters,
  // the pre-read size rejection, the name-based mime fallback incl. HEIC)
  // now runs under flutter test against an injected pick seam
  // (test/data/feedback/image_picker_attachment_source_test.dart), so only
  // a five-line static plugin wrapper remains uncovered — not enough to
  // warrant hiding the whole file from the gates' denominator, and keeping
  // the exclusion would have let the newly tested logic silently regress.
  const CoverageExclusion(
    'lib/data/export/account_export_writer.dart',
    'AccountExportWriter wraps path_provider (temp directory) and '
        'share_plus (the platform share sheet), neither of which can run '
        'under flutter test. All content-shaped logic lives in the pure '
        'lib/domain/export/account_export.dart builder it wraps, which is '
        'unit-tested directly; this file is proven by the U7 device '
        'checklist instead, same treatment as google_sign_in_client.dart.',
  ),
  const CoverageExclusion(
    'lib/data/export/csv_export_writer.dart',
    'PlatformCsvExportWriter wraps path_provider (temp directory) and '
        'share_plus (the platform share sheet), neither of which can run '
        'under flutter test. All content-shaped logic lives in the pure '
        'lib/domain/export/csv_export.dart builders it wraps, which are '
        'unit-tested directly; this file is proven by the device checklist '
        'instead, same treatment as account_export_writer.dart.',
  ),
  const CoverageExclusion(
    'lib/data/import/import_file_picker.dart',
    'pickImportFile wraps the file_picker plugin (FilePicker.pickFile) and '
        "the returned PlatformFile's readAsBytes, neither of which can run "
        'under flutter test. All content-shaped logic lives in the pure '
        'lib/domain/import/account_import.dart parser it feeds, which is '
        'unit-tested directly; this file is proven by the device checklist '
        'instead, same treatment as account_export_writer.dart.',
  ),
  const CoverageExclusion(
    'lib/data/notifications/firebase_push_token_source.dart',
    'FirebasePushTokenSource wraps firebase_core/firebase_messaging calls '
        '(Firebase.initializeApp, requestPermission, getToken, and the two '
        'FirebaseMessaging stream getters) that cannot run under flutter '
        'test -- but, per review #10, NOT because the file has no branching '
        'worth testing in isolation: an earlier version of this rationale '
        'said exactly that while quietly excluding the sequencing bugs #4 '
        '(missing requestPermission()) and #5 (FirebaseMessaging.instance '
        'touched before Firebase.initializeApp() completed) from ever being '
        'exercised. buildFirebaseOptions(), the one piece of pure branching '
        'this file has, is now a directly unit-tested top-level function '
        'despite living in this excluded file. PushRegistrationCoordinator '
        '(the ordering/lifecycle logic) is covered directly against a fake '
        'PushTokenSource.',
  ),
  // Issue #173: the health-channel platform pins. The constructor is the
  // entire executable surface of each file -- everything real they bind
  // to is Swift/Kotlin and can never run under flutter test, so they get
  // the google_sign_in_client.dart treatment. Two deliberate non-exclusions
  // keep the exclusion honest (the firebase_push_token_source review above
  // is the cautionary precedent): ALL shared logic -- the guard-ordering
  // engine, codec, and error mapping -- lives in
  // lib/data/health/health_channel.dart and health_channel_codec.dart,
  // which are NOT excluded and are directly tested against a fake
  // MethodChannel in test/data/health/, so excluding these two pins hides
  // no testable logic from the gates. The actual Swift/Kotlin adapter
  // files (ios/Runner/AppDelegate.swift,
  // android/.../HealthConnectAdapter.kt) never appear in lcov at all --
  // coverage instruments Dart only -- which is why the issue's
  // "exclude the native files" checklist item lands on their Dart-side
  // pins instead.
  const CoverageExclusion(
    'lib/data/health/ios_health_channel.dart',
    'IOSHealthChannel pins the shared MethodChannelHealthPlatform engine '
        'to the Swift HKHealthStore handler (AppDelegate.swift, issue '
        '#173); the constructor is the whole file, the behavior is '
        'native-only, and every piece of shared logic is tested in the '
        'non-excluded health_channel.dart/health_channel_codec.dart — '
        'same treatment as google_sign_in_client.dart.',
  ),
  const CoverageExclusion(
    'lib/data/health/android_health_channel.dart',
    'AndroidHealthChannel pins the shared MethodChannelHealthPlatform '
        'engine to the Kotlin HealthConnectClient handler '
        '(HealthConnectAdapter.kt, issue #173); constructor-only, '
        'native-backed, with all shared logic tested in the non-excluded '
        'health_channel.dart/health_channel_codec.dart — same treatment '
        'as google_sign_in_client.dart.',
  ),
];

final RegExp _generatedCodePattern = RegExp(r'\.g\.dart$');

/// `flutter gen-l10n` output (issue #160): `lib/l10n/app_localizations.dart`
/// and its per-locale implementations (`app_localizations_en.dart`, ...) are
/// machine-generated from `lib/l10n/app_en.arb` and committed, same
/// treatment as `**/*.g.dart` above — the suffix glob cannot reach them
/// because gen-l10n names its outputs after the ARB template. The ARB's own
/// guard is `test/ui/l10n_test.dart`'s copy-parity suite, which asserts
/// every generated getter against the exact literal it replaced.
final RegExp _genL10nPattern = RegExp(r'lib/l10n/app_localizations.*\.dart$');

/// `dart run drift_dev schema generate` output (issue #200): every file
/// under `test/data/db/generated_migrations/` is machine-generated from the
/// `drift_schemas/*.json` dumps and rewritten wholesale by that command, same
/// treatment as `**/*.g.dart` above — a directory-prefix glob rather than a
/// literal path in [excludedLibFilePaths] because (a) it lives under `test/`,
/// not `lib/`, so it is out of scope for [nonExcludedLibDartFiles] and
/// `mutation_gate.dart` regardless, and (b) the file names themselves change
/// as more schema versions are dumped (`schema_v1.dart`, `schema_v2.dart`,
/// ...).
final RegExp _driftSchemaMigrationHelperPattern =
    RegExp(r'test/data/db/generated_migrations/.*\.dart$');

/// [excludedLibFilePaths] compiled to anchored, escaped `RegExp`s, plus the
/// generated-code globs — the matcher [isExcluded] actually uses.
final List<RegExp> coveragePatterns = [
  _generatedCodePattern,
  _genL10nPattern,
  _driftSchemaMigrationHelperPattern,
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
