/// Pins the raw-DOM and URL-launch surface of `lib/`.
///
/// Written for epic #831 (slice 5), whose review is recorded in
/// `docs/web/xss-surface-review.md`. The Flutter web build that review was
/// about is gone (issue #1257); the scans stay because each still guards
/// something:
///
/// * **Direct browser-DOM imports.** No file in `lib/` may import
///   `package:web`/`dart:html`/`dart:js_interop`/`dart:js`/`dart:js_util`/
///   `dart:ui_web`. The app targets iOS and Android only, so such an import
///   would be the first step of a browser build coming back by accident.
///   (`tool/web_domain/`, which compiles the domain module for the React
///   web client, lives outside `lib/` and is not scanned.)
/// * **Raw-HTML sinks.** No `innerHTML`/`setInnerHtml`/`HtmlElementView`/
///   `dangerouslySetInnerHTML` string may appear in `lib/`.
/// * **URL launching.** A bare `launchUrl(`/`launchUrlString(` call may live
///   only in the one scheme-gated helper, so a user-authored URL can never
///   reach the platform launcher with an unvalidated scheme. This one is
///   not specific to any platform.
///
/// Source-text scans pin the shape. Each detector gets its own
/// falsification coverage so a silently broken match cannot leave the guard
/// vacuously green.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files permitted to import a browser-DOM library directly. Empty: the
/// app has no browser build.
const Set<String> kRawDomImportAllowlist = <String>{};

/// Files permitted a bare `launchUrl(`/`launchUrlString(` call. The one
/// scheme-gated helper; see `kDefaultLaunchSchemes` in it.
const Set<String> kLaunchUrlCallSiteAllowlist = <String>{
  'lib/ui/components/safe_launch_url.dart',
};

/// A whole `import`/`export` directive, from the keyword to its `;`.
/// Anchored at line start so prose mentioning a directive is not matched.
final _directive = RegExp(
  r'''^\s*(?:import|export)\s+[^;]*;''',
  multiLine: true,
);

/// Every quoted URI inside one directive — covers each conditional branch.
final _quotedUri = RegExp(r'''['"]([^'"]+)['"]''');

/// The quoted URIs a directive in [contents] refers to. `import
/// 'stub.dart' if (dart.library.js_interop) 'web.dart'` yields both project
/// paths; the `dart.library.…` condition is not quoted, so it is not one.
Iterable<String> importedUris(String contents) sync* {
  for (final directive in _directive.allMatches(contents)) {
    for (final uri in _quotedUri.allMatches(directive.group(0)!)) {
      yield uri.group(1)!;
    }
  }
}

/// Whether [uri] names a browser-DOM library this app must not import
/// outside the allowlist.
bool isRawDomLibrary(String uri) =>
    uri == 'dart:html' ||
    uri == 'dart:js' ||
    uri == 'dart:js_util' ||
    uri == 'dart:js_interop' ||
    uri == 'dart:ui_web' ||
    uri.startsWith('package:web/');

/// Whether [contents] imports a browser-DOM library directly.
bool importsRawDom(String contents) => importedUris(contents).any(isRawDomLibrary);

/// The raw-HTML sinks forbidden anywhere in `lib/`.
final _rawDomSink = RegExp(
  r'innerHTML|setInnerHtml|HtmlElementView|dangerouslySetInnerHTML',
);

/// Every forbidden raw-HTML sink token in [contents].
List<String> rawDomSinksIn(String contents) =>
    _rawDomSink.allMatches(contents).map((m) => m.group(0)!).toList();

/// A bare `launchUrl(`/`launchUrlString(` call — not `_launchUrl(` and not
/// `safeLaunchUrl(`, both of which have a word character before `launch`.
final _bareLaunchCall = RegExp(r'\blaunchUrl(?:String)?\s*\(');

/// Whether [contents] contains a bare `launchUrl(`/`launchUrlString(` call.
bool hasBareLaunchUrlCall(String contents) =>
    _bareLaunchCall.hasMatch(contents);

/// [contents] with `//` line comments and `/* */` block comments removed, so
/// a doc comment that merely *names* a forbidden token or references the
/// helper does not trip the scans. String literals are stripped along with
/// the comment that follows a `//` inside them, which is harmless here: a
/// forbidden sink or launch call is never hidden inside a URL.
String stripComments(String contents) => contents
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Every `.dart` file under [root], with posix-normalised paths.
List<File> _dartFilesUnder(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _posix(File file) => file.path.replaceAll(r'\', '/');

void main() {
  group('raw browser-DOM imports', () {
    test('no file in lib/ imports package:web / dart:html / '
        'dart:js_interop', () {
      final files = _dartFilesUnder('lib');
      expect(files, isNotEmpty, reason: 'scanned zero files — check the path');

      final offenders = <String>[];
      for (final file in files) {
        final path = _posix(file);
        if (kRawDomImportAllowlist.contains(path)) continue;
        if (importsRawDom(file.readAsStringSync())) offenders.add(path);
      }
      expect(
        offenders,
        isEmpty,
        reason: 'lib/ has no browser build: a direct browser-DOM import '
            'must not appear:\n${offenders.join('\n')}',
      );
    });

    test('detector flags the direct forms and ignores the conditional '
        'condition / project imports', () {
      expect(importsRawDom("import 'package:web/web.dart' as web;"), isTrue);
      expect(importsRawDom("import 'dart:html';"), isTrue);
      expect(importsRawDom("import 'dart:js_interop';"), isTrue);
      expect(
        importsRawDom("import 'stub.dart'\n"
            "    if (dart.library.js_interop) 'web.dart';"),
        isFalse,
        reason: 'the js_interop *condition* is not an import',
      );
      expect(
        importsRawDom("import 'package:lunarlog/domain/models/profile.dart';"),
        isFalse,
      );
    });
  });

  group('no raw-HTML sinks in lib/', () {
    test('innerHTML / setInnerHtml / HtmlElementView / '
        'dangerouslySetInnerHTML never appear', () {
      final files = _dartFilesUnder('lib');
      expect(files, isNotEmpty, reason: 'scanned zero files — check the path');

      final offenders = <String>[];
      for (final file in files) {
        final sinks = rawDomSinksIn(stripComments(file.readAsStringSync()));
        if (sinks.isNotEmpty) offenders.add('${_posix(file)}: ${sinks.join(', ')}');
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Flutter text is never HTML-parsed; a raw-DOM sink is the one '
            'path that would break that, so it must not exist:\n'
            '${offenders.join('\n')}',
      );
    });

    test('detector flags the sink forms', () {
      expect(rawDomSinksIn("el.innerHTML = userText;"), isNotEmpty);
      expect(rawDomSinksIn('node.setInnerHtml(value)'), isNotEmpty);
      expect(rawDomSinksIn('const HtmlElementView(viewType: x)'), isNotEmpty);
      expect(rawDomSinksIn('dangerouslySetInnerHTML'), isNotEmpty);
      expect(rawDomSinksIn('Text(userText)'), isEmpty);
    });
  });

  group('launchUrl call sites are scheme-gated', () {
    test('a bare launchUrl(/launchUrlString( lives only in the allowlisted '
        'helper', () {
      final files = _dartFilesUnder('lib');
      expect(files, isNotEmpty, reason: 'scanned zero files — check the path');

      final offenders = <String>[];
      for (final file in files) {
        final path = _posix(file);
        if (kLaunchUrlCallSiteAllowlist.contains(path)) continue;
        if (hasBareLaunchUrlCall(stripComments(file.readAsStringSync()))) {
          offenders.add(path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'route every launch through safeLaunchUrl (the scheme gate) '
            'instead of calling url_launcher directly:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the sole call site exists and gates on the scheme allowlist', () {
      final files = _dartFilesUnder('lib');
      final sites = [
        for (final file in files)
          if (hasBareLaunchUrlCall(stripComments(file.readAsStringSync())))
            _posix(file),
      ];
      expect(sites, kLaunchUrlCallSiteAllowlist.toList(),
          reason: 'the guard must not be vacuous — the helper is the one '
              'call site');

      final helper =
          File('lib/ui/components/safe_launch_url.dart').readAsStringSync();
      for (final scheme in ["'http'", "'https'", "'mailto'", "'tel'", "'sms'"]) {
        expect(helper, contains(scheme),
            reason: '$scheme must stay in kDefaultLaunchSchemes');
      }
      expect(helper, contains('isLaunchSchemeAllowed('),
          reason: 'the helper must refuse a disallowed scheme before calling '
              'the platform launcher');
    });

    test('the device-settings launcher routes through safeLaunchUrl and no '
        'longer calls launchUrl directly', () {
      final source = stripComments(
          File('lib/ui/gate/device_settings_launcher.dart').readAsStringSync());
      expect(source, contains('safeLaunchUrl('));
      expect(hasBareLaunchUrlCall(source), isFalse);
    });

    test('detector flags a bare call and ignores the helper / private name',
        () {
      expect(hasBareLaunchUrlCall('await launchUrl(uri);'), isTrue);
      expect(hasBareLaunchUrlCall('await launchUrlString(uri);'), isTrue);
      expect(hasBareLaunchUrlCall('await safeLaunchUrl(uri);'), isFalse);
      expect(hasBareLaunchUrlCall('Future<bool> _launchUrl(Uri u) => x;'), isFalse);
    });
  });
}
