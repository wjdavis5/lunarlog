/// Epic #831 slice 4: pin the browser-URL cleanup's production halves.
///
/// The interesting behaviour — *when* the cleaner is invoked, and that the
/// cleaned URL drops the spent `code` while keeping everything else — is
/// covered by `test/data/web_url_cleaner_test.dart` (the pure helper) and
/// the web cases in `test/data/supabase_auth_service_test.dart`. What those
/// cannot execute is the platform split itself: `flutter test` never runs
/// `window.history`. These two source facts pin it instead.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('WebUrlCleaner platform split', () {
    test('the web half rewrites the current history entry with replaceState, '
        'never pushState (no extra Back entry)', () {
      final source = read('lib/data/auth/web_url_cleaner_web.dart');
      expect(source, contains('replaceState('));
      expect(source, isNot(contains('pushState(')));
    });

    test('the native half is a deliberate no-op', () {
      final source = read('lib/data/auth/web_url_cleaner_stub.dart');
      expect(source, contains('void replaceBrowserUrl(Uri uri) {}'));
    });

    test('the web half is compiled only under the js_interop conditional '
        'import, so a native build never sees package:web', () {
      final source = read('lib/data/auth/web_url_cleaner.dart');
      expect(source, contains("if (dart.library.js_interop)"));
      final stub = read('lib/data/auth/web_url_cleaner_stub.dart');
      expect(stub, isNot(contains('package:web')));
    });
  });
}
