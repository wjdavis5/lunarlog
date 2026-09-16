/// Issue #738's single-seam pin: `LUNARLOG_ENABLE_MFA` is read exactly
/// once — `AppConfig.mfaEnabled` in `lib/config.dart` — and that constant
/// is resolved exactly once — `AuthController`'s constructor in
/// `lib/ui/account/auth_controller.dart`. Every other MFA gate
/// (`MfaSettingsSection`, `MfaEnrollScreen`, `ensureAal2`, the app shell)
/// consults `AuthController.mfaEnabled`, never the flag itself, so a
/// future build flag (issue #739's QA-build step-up bypass) ORs into one
/// resolver instead of scattering a second read of the define.
///
/// Enforced the same way `layering_test.dart` enforces its edges: walk the
/// source tree with `dart:io`, no lint plugin, no new dependency. Comment
/// lines are stripped before matching, mirroring layering_test's
/// "a doc comment that merely mentions a forbidden import is not matched"
/// rule — several files legitimately *document* the flag and the resolver
/// by name without reading either.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The compile-time define name (issue #738): `bool.fromEnvironment`'s
/// argument is the one and only read of the flag.
final _defineLiteral = RegExp(r'LUNARLOG_ENABLE_MFA');

/// A code reference to the resolved constant, whitespace-tolerant.
final _seamReference = RegExp(r'\bAppConfig\s*\.\s*mfaEnabled\b');

/// Strips `//`-comment lines (doc comments included) so prose mentioning
/// the flag or the seam is not matched — the same intent as layering_test
/// anchoring its detector on line-start directives.
String stripComments(String contents) => contents
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

List<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Posix-normalised paths of [files] whose code (comments stripped)
/// matches [pattern].
List<String> _codeMatches(List<File> files, RegExp pattern) => [
      for (final file in files)
        if (pattern.hasMatch(stripComments(file.readAsStringSync())))
          file.path.replaceAll(r'\', '/'),
    ];

void main() {
  final files = _libDartFiles();

  test('the lib/ tree was actually scanned', () {
    expect(files, isNotEmpty, reason: 'scanned zero files — check the path');
  });

  test('LUNARLOG_ENABLE_MFA appears in code only in lib/config.dart', () {
    expect(_codeMatches(files, _defineLiteral), ['lib/config.dart'],
        reason: 'the define must be read once, through AppConfig.mfaEnabled '
            '— a second read belongs in that resolver, not beside it');
  });

  test('AppConfig.mfaEnabled is resolved in code only by AuthController',
      () {
    expect(_codeMatches(files, _seamReference),
        ['lib/ui/account/auth_controller.dart'],
        reason: 'every other gate must consult AuthController.mfaEnabled '
            '(or a value passed down from it), never the constant directly');
  });

  // Gives the guard its own teeth, in layering_test's falsification style:
  // a detector that silently stopped matching would leave both scans above
  // passing on a clean tree and catch nothing on a dirty one.
  test('detects the violations the two scans exist to catch', () {
    // The define read outside the seam (even mid-expression, and with
    // comment lines above it).
    expect(
      _defineLiteral.hasMatch(stripComments('''
/// Docs mention LUNARLOG_ENABLE_MFA harmlessly.
static const bool x = bool.fromEnvironment('LUNARLOG_ENABLE_MFA');
''')),
      isTrue,
      reason: 'a code read of the define must be flaggable wherever it sits',
    );
    // The constant referenced outside the resolver.
    expect(
      _seamReference.hasMatch(
          stripComments('final bool on = AppConfig.mfaEnabled;')),
      isTrue,
      reason: 'a direct code reference to the constant must be flaggable',
    );
    // Prose alone (the whole file is comments) must not be.
    expect(
      _defineLiteral.hasMatch(stripComments(
          '/// Set LUNARLOG_ENABLE_MFA=true to turn MFA back on (#738).')),
      isFalse,
      reason: 'a doc comment mentioning the define is not a read of it',
    );
    expect(
      _seamReference.hasMatch(stripComments(
          '/// Docs say AuthController.mfaEnabled is the resolver.')),
      isFalse,
      reason: 'a doc comment mentioning the constant is not a reference',
    );
  });
}
