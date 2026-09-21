/// Unit tests for the widget quick-log intent codec (issue #141): the
/// URI build/parse round-trip and the strictness of the parser — only the
/// exact scheme/host/parameter shape is a quick-log intent; anything else
/// (the auth callback's host, the plain open host, a missing profile)
/// parses to null so it can never fall through to "write something".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/widget/widget_quick_log_intent.dart';

void main() {
  group('widgetQuickLogUri', () {
    test('builds the launch URI the plugin recognizes', () {
      // The `homeWidget` marker parameter is the plugin's own
      // widget-origin signal (its iOS isWidgetUrl checks for it).
      expect(
        widgetQuickLogUri('PROFILE1'),
        'lunarlog://widget-quick-log?homeWidget=1&profile=PROFILE1',
      );
    });
  });

  group('parseWidgetQuickLogUri', () {
    test('round-trips the built URI', () {
      final intent = parseWidgetQuickLogUri(
        Uri.parse(widgetQuickLogUri('PROFILE1')),
      );
      expect(intent, isNotNull);
      expect(intent!.profileId, 'PROFILE1');
    });

    test('rejects a foreign scheme', () {
      expect(
        parseWidgetQuickLogUri(
            Uri.parse('https://widget-quick-log?profile=PROFILE1')),
        isNull,
      );
    });

    test('rejects the auth-callback host', () {
      // The auth service owns lunarlog://auth-callback; the widget
      // parser must never accept it.
      expect(
        parseWidgetQuickLogUri(
            Uri.parse('lunarlog://auth-callback?profile=PROFILE1')),
        isNull,
      );
    });

    test('rejects the plain open host', () {
      expect(
        parseWidgetQuickLogUri(
            Uri.parse(widgetOpenUri())),
        isNull,
      );
    });

    test('rejects a quick-log URI with no profile parameter', () {
      expect(
        parseWidgetQuickLogUri(
            Uri.parse('lunarlog://widget-quick-log?homeWidget=1')),
        isNull,
      );
    });

    test('rejects a quick-log URI with an empty profile parameter', () {
      expect(
        parseWidgetQuickLogUri(
            Uri.parse('lunarlog://widget-quick-log?profile=')),
        isNull,
      );
    });
  });

  group('WidgetQuickLogIntent equality', () {
    test('same profile id is equal, different is not', () {
      const a = WidgetQuickLogIntent(profileId: 'p1');
      expect(a, a);
      expect(a, const WidgetQuickLogIntent(profileId: 'p1'));
      expect(a.hashCode, const WidgetQuickLogIntent(profileId: 'p1').hashCode);
      expect(a, isNot(const WidgetQuickLogIntent(profileId: 'p2')));
      expect(a, isNot(Object()));
    });

    test('toString never leaks the profile id', () {
      final text = const WidgetQuickLogIntent(profileId: 'SECRET').toString();
      expect(text, isNot(contains('SECRET')));
    });
  });

  group('widgetOpenUri', () {
    test('carries the plugin marker but no action host', () {
      expect(widgetOpenUri(), 'lunarlog://widget-open?homeWidget=1');
    });
  });
}
