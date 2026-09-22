/// Epic #831 slice 5: the scheme gate behind every external launch. The
/// architecture test (`test/architecture/web_dom_surface_test.dart`) pins
/// that this is the only `launchUrl` call site; this proves the gate itself
/// fails closed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/safe_launch_url.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

void main() {
  group('isLaunchSchemeAllowed', () {
    test('allows the default web/mail/phone schemes case-insensitively', () {
      for (final scheme in ['http', 'https', 'mailto', 'tel', 'HTTPS']) {
        expect(isLaunchSchemeAllowed(scheme, kDefaultLaunchSchemes), isTrue,
            reason: '$scheme must be allowed');
      }
    });

    test('rejects an empty scheme and every dangerous/unknown scheme', () {
      for (final scheme in ['', 'javascript', 'data', 'file', 'intent',
        'app-settings', 'lunarlog']) {
        expect(isLaunchSchemeAllowed(scheme, kDefaultLaunchSchemes), isFalse,
            reason: '"$scheme" must be refused');
      }
    });
  });

  group('safeLaunchUrl', () {
    test('a disallowed scheme returns false and never launches', () async {
      var calls = 0;
      final launched = await safeLaunchUrl(
        Uri.parse('javascript:alert(1)'),
        launch: (url, {LaunchMode mode = LaunchMode.platformDefault}) {
          calls++;
          return Future.value(true);
        },
      );
      expect(launched, isFalse);
      expect(calls, 0, reason: 'the platform launcher must never be reached');
    });

    test('an allowed scheme launches with the same url and mode', () async {
      final url = Uri.parse('https://example.com/x');
      Uri? seen;
      LaunchMode? seenMode;
      final ok = await safeLaunchUrl(
        url,
        mode: LaunchMode.externalApplication,
        launch: (u, {LaunchMode mode = LaunchMode.platformDefault}) {
          seen = u;
          seenMode = mode;
          return Future.value(true);
        },
      );
      expect(ok, isTrue);
      expect(seen, url);
      expect(seenMode, LaunchMode.externalApplication);
    });

    test('a caller may supply its own allowlist (device settings schemes)',
        () async {
      var calls = 0;
      Future<bool> fake(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) {
        calls++;
        return Future.value(true);
      }

      final refused = await safeLaunchUrl(
        Uri.parse('app-settings:'),
        allowedSchemes: const {'http'},
        launch: fake,
      );
      expect(refused, isFalse);
      expect(calls, 0);

      final allowed = await safeLaunchUrl(
        Uri.parse('app-settings:'),
        allowedSchemes: const {'app-settings', 'intent'},
        launch: fake,
      );
      expect(allowed, isTrue);
      expect(calls, 1);
    });
  });
}
