/// Epic #831 slice 4: [cleanAuthUrl] — the pure half of the browser-URL
/// cleanup. The spent PKCE `code` (or a provider `error` the link carried)
/// is removed while the scheme, authority, path, fragment, parameter order,
/// duplicate keys, and every unrelated parameter are preserved, so a reload
/// neither replays a spent exchange nor shows a bogus expired-link failure.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/auth/web_url_cleaner.dart';

void main() {
  group('cleanAuthUrl', () {
    test('removes the spent code and preserves the path and other params',
        () {
      final cleaned = cleanAuthUrl(Uri.parse(
          'https://app.lunarlog.app/auth/callback?code=abc&foo=bar&baz=1'));
      expect(cleaned.toString(),
          'https://app.lunarlog.app/auth/callback?foo=bar&baz=1');
    });

    test('removes provider error params (and a code, if both are present)',
        () {
      final cleaned = cleanAuthUrl(Uri.parse(
          'https://app.lunarlog.app/auth/callback'
          '?error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired'
          '&code=abc&foo=bar'));
      expect(cleaned.toString(),
          'https://app.lunarlog.app/auth/callback?foo=bar');
      expect(cleaned.toString(), isNot(contains('access_denied')));
      expect(cleaned.toString(), isNot(contains('expired')));
      expect(cleaned.toString(), isNot(contains('code')));
    });

    test('removes every auth parameter the classifier keys on', () {
      final cleaned = cleanAuthUrl(Uri.parse(
          'https://x/auth/callback?code=c&error=e&error_code=ec'
          '&error_description=ed&access_token=at&refresh_token=rt&type=recovery'
          '&keep=yes'));
      expect(cleaned.toString(), 'https://x/auth/callback?keep=yes');
    });

    test('parameter order and duplicate keys of the kept params survive', () {
      final cleaned = cleanAuthUrl(
          Uri.parse('https://x/p?b=2&code=c&a=1&b=3&c=4'));
      expect(cleaned.toString(), 'https://x/p?b=2&a=1&b=3&c=4');
    });

    test('a fragment is preserved; auth params inside it are removed too',
        () {
      expect(
        cleanAuthUrl(Uri.parse('https://x/p?keep=1#section')).toString(),
        'https://x/p?keep=1#section',
      );
      expect(
        cleanAuthUrl(
                Uri.parse('https://x/p?keep=1#code=abc&keep=2'))
            .toString(),
        'https://x/p?keep=1#keep=2',
      );
    });

    test('a URL with no auth parameter is returned unchanged', () {
      final uri = Uri.parse('https://x/p?foo=bar');
      expect(identical(cleanAuthUrl(uri), uri), isTrue);
    });

    test('an empty query loses the "?" rather than leaving one behind', () {
      final cleaned = cleanAuthUrl(Uri.parse('https://x/auth/callback?code=a'));
      expect(cleaned.toString(), 'https://x/auth/callback');
      expect(cleaned.hasQuery, isFalse);
    });

    test('the native custom-scheme callback is cleanable the same way', () {
      expect(
        cleanAuthUrl(Uri.parse('lunarlog://auth-callback?code=a&x=1'))
            .toString(),
        'lunarlog://auth-callback?x=1',
      );
    });

    test('percent-encoded parameter names are decoded before matching', () {
      final cleaned =
          cleanAuthUrl(Uri.parse('https://x/p?co%64e=abc&foo=1'));
      expect(cleaned.toString(), 'https://x/p?foo=1');
    });
  });
}
