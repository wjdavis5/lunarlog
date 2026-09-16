/// Issue #739's single-seam pin: `LUNARLOG_QA_BUILD` is read exactly
/// once — `AppConfig.qaBuild` in `lib/config.dart`. Every QA-build gate
/// (`GateController`'s launch/relock/re-auth bypasses, `ensureAal2`'s
/// step-up bypass, `LunarLogApp`'s banner and title suffix, the Settings
/// relock toggle, the About version line) consults that constant (or a
/// value injected from it), never the define itself, so a future build
/// flag composes by OR-ing into one of those gates instead of scattering
/// a second read of the define.
///
/// Mirrors `mfa_flag_seam_test.dart` (#738) in structure, with one
/// deliberate difference: unlike `AppConfig.mfaEnabled` (resolved by
/// exactly one downstream resolver, `AuthController`'s constructor), the
/// QA flag has no single resolver — it is consumed by several
/// independently-injected gates — so the second pin here is that the
/// resolved constant is *declare-once* rather than referenced-once: no
/// file outside `lib/config.dart` re-derives it from the environment.
/// Consumers reference `AppConfig.qaBuild` directly, which the define
/// scan below proves can only ever resolve to the one const.
///
/// Enforced the same way `layering_test.dart` enforces its edges: walk
/// the source tree with `dart:io`, no lint plugin, no new dependency.
/// Comment lines are stripped before matching, mirroring layering_test's
/// "a doc comment that merely mentions a forbidden import is not matched"
/// rule — several files legitimately *document* the flag and the seam
/// by name without reading either.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The compile-time define name (issue #739): `bool.fromEnvironment`'s
/// argument is the one and only read of the flag.
final _defineLiteral = RegExp(r'LUNARLOG_QA_BUILD');

/// A code reference to the resolved constant, whitespace-tolerant.
final _seamReference = RegExp(r'\bAppConfig\s*\.\s*qaBuild\b');

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

  test('LUNARLOG_QA_BUILD appears in code only in lib/config.dart', () {
    expect(_codeMatches(files, _defineLiteral), ['lib/config.dart'],
        reason: 'the define must be read once, through AppConfig.qaBuild '
            '— a second read belongs in that seam, not beside it');
  });

  test('AppConfig.qaBuild is consumed through injection seams, not '
      're-derived anywhere', () {
    // The deliberate consumer set (see this file's library doc): each of
    // these resolves the const once — as a nullable constructor parameter
    // default or a default-valued function parameter — so tests can
    // exercise both flag values in a single default-off run. Extending
    // the set is fine; do it by adding a new injection seam in the same
    // idiom, not by branching on the define elsewhere.
    const expectedConsumers = [
      'lib/app.dart',
      'lib/gate_controller.dart',
      'lib/ui/account/mfa_step_up_dialog.dart',
      'lib/ui/settings/about_section.dart',
      'lib/ui/settings/settings_screen.dart',
    ];
    final consumers = _codeMatches(files, _seamReference)
      ..remove('lib/config.dart');
    // `unorderedEquals`: the pin must not depend on the platform's
    // directory-listing order.
    expect(consumers, unorderedEquals(expectedConsumers),
        reason: 'AppConfig.qaBuild must be resolved through the injection '
            'seams above — a new consumer needs its own injection seam, '
            'added here deliberately, never a direct define read');
  });

  // Gives the guard its own teeth, in layering_test's falsification style:
  // a detector that silently stopped matching would leave both scans above
  // passing on a clean tree and catch nothing on a dirty one.
  test('detects the violations the scans exist to catch', () {
    // The define read outside the seam (even mid-expression, and with
    // comment lines above it).
    expect(
      _defineLiteral.hasMatch(stripComments('''
/// Docs mention LUNARLOG_QA_BUILD harmlessly.
static const bool x = bool.fromEnvironment('LUNARLOG_QA_BUILD');
''')),
      isTrue,
      reason: 'a code read of the define must be flaggable wherever it sits',
    );
    // The constant referenced outside the known consumer set.
    expect(
      _seamReference.hasMatch(
          stripComments('final bool on = AppConfig.qaBuild;')),
      isTrue,
      reason: 'a direct code reference to the constant must be flaggable',
    );
    // Prose alone (the whole file is comments) must not be.
    expect(
      _defineLiteral.hasMatch(stripComments(
          '/// Set LUNARLOG_QA_BUILD=true to cut a QA build (#739).')),
      isFalse,
      reason: 'a doc comment mentioning the define is not a read of it',
    );
    expect(
      _seamReference.hasMatch(stripComments(
          '/// Docs say AppConfig.qaBuild is the seam.')),
      isFalse,
      reason: 'a doc comment mentioning the constant is not a reference',
    );
  });
}
