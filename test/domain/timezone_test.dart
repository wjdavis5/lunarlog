/// Unit tests for canonical IANA timezone resolution (finding #23 in #37, issue #46).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/util/timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUp(() {
    tzdata.initializeTimeZones();
  });

  // setLocalLocation mutates the process-global tz.local; restore UTC so
  // file order cannot leak zones into other tests.
  tearDown(() {
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  group('resolveCurrentTimeZone', () {
    test('returns canonical IANA timezone identifier', () {
      final initial = resolveCurrentTimeZone();
      expect(initial, isNotEmpty);
      expect(isValidIanaTimeZone(initial), isTrue);
    });

    test('reflects location configured via tz.setLocalLocation', () {
      final ny = tz.getLocation('America/New_York');
      tz.setLocalLocation(ny);
      expect(resolveCurrentTimeZone(), 'America/New_York');

      final paris = tz.getLocation('Europe/Paris');
      tz.setLocalLocation(paris);
      expect(resolveCurrentTimeZone(), 'Europe/Paris');

      final tokyo = tz.getLocation('Asia/Tokyo');
      tz.setLocalLocation(tokyo);
      expect(resolveCurrentTimeZone(), 'Asia/Tokyo');
    });
  });

  group('isValidIanaTimeZone', () {
    test('accepts valid canonical IANA timezone identifiers', () {
      expect(isValidIanaTimeZone('America/New_York'), isTrue);
      expect(isValidIanaTimeZone('America/Chicago'), isTrue);
      expect(isValidIanaTimeZone('Europe/London'), isTrue);
      expect(isValidIanaTimeZone('Asia/Tokyo'), isTrue);
      expect(isValidIanaTimeZone('Etc/UTC'), isTrue);
      expect(isValidIanaTimeZone('UTC'), isTrue);
    });

    test('rejects platform abbreviations and invalid names', () {
      expect(isValidIanaTimeZone('EDT'), isFalse);
      expect(isValidIanaTimeZone('CDT'), isFalse);
      expect(isValidIanaTimeZone('PDT'), isFalse);
      expect(isValidIanaTimeZone('GMT+10'), isFalse);
      expect(isValidIanaTimeZone(''), isFalse);
      expect(isValidIanaTimeZone('Not/A_Real_Timezone'), isFalse);
    });
  });
}
