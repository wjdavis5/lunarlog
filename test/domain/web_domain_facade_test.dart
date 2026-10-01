/// Unit tests for the web domain facade itself (issue #1251): the request
/// decoding, the error envelope (the facade never throws across the
/// boundary), the suppression/birth-control resolution order, the output
/// serialization shapes, and the export builder's determinism. The
/// fixture-level pinning against the Dart domain and the compiled module
/// lives in `web_domain_fixtures_test.dart` and the webapp's Vitest parity
/// suite; this file pins the codec behavior those fixtures do not reach.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../tool/web_domain/facade.dart';
import '../../tool/web_domain/iana_aliases.dart';

void main() {
  // The facade initializes the tz database lazily on its first call; the
  // zone-assertions below must not depend on test ordering, so initialize
  // it here too (idempotent — it just reloads the same data).
  setUpAll(tzdata.initializeTimeZones);

  Map<String, Object?> call(String method, Object? request) {
    final response = handleFacadeCall(method, jsonEncode(request));
    return jsonDecode(response) as Map<String, Object?>;
  }

  Map<String, Object?> bleedEntry(
    String id,
    String localDate, {
    String flow = 'medium',
    bool pms = false,
  }) => {
    'id': id,
    'profileId': 'p1',
    'localDate': localDate,
    'tz': 'UTC',
    'flow': flow,
    'tags': const <String>[],
    'note': null,
    'notePrivate': false,
    'pms': pms,
    'source': 'manual',
    'sourceId': null,
    'importId': null,
    'updatedAt': '${localDate}T12:00:00.000Z',
  };

  group('envelope', () {
    test('unknown method is an error, not a throw', () {
      final response = call('teleport', {});
      expect(response['ok'], false);
      expect(response['error'], contains('unknown facade method'));
    });

    test('malformed JSON is an error envelope', () {
      final response = jsonDecode(
        handleFacadeCall('predict', '{not json'),
      ) as Map<String, Object?>;
      expect(response['ok'], false);
      expect(response['error'], contains('not valid JSON'));
    });

    test('a non-object request is an error envelope', () {
      final response = call('predict', [1, 2, 3]);
      expect(response['ok'], false);
      expect(response['error'], contains('JSON object'));
    });

    test('a success envelope wraps the method data', () {
      final response = call('validateDayEntryDate', {
        'date': '2026-09-30',
        'today': '2026-09-30',
      });
      expect(response['ok'], true);
      expect(response['data'], {'status': 'valid'});
    });
  });

  group('request decoding', () {
    test('missing today / tz / entries are named errors', () {
      expect(
        call('predict', {'tz': 'UTC', 'entries': const <Object>[]})['error'],
        contains('today'),
      );
      expect(
        call('predict', {
          'today': '2026-09-30',
          'entries': const <Object>[],
        })['error'],
        contains('tz'),
      );
      expect(
        call('predict', {'today': '2026-09-30', 'tz': 'UTC'})['error'],
        contains('entries'),
      );
    });

    test('an unknown IANA zone is an error, never a silent UTC fallback', () {
      final response = call('predict', {
        'today': '2026-09-30',
        'tz': 'Mars/Olympus_Mons',
        'entries': const <Object>[],
      });
      expect(response['ok'], false);
      expect(response['error'], contains('unknown IANA time zone'));
    });

    test('the bare UTC link name aliases to the database zone', () {
      // `tz` is consumed by the date-math methods (validateDayEntryDate
      // does no zone math), so exercise the alias through one of those.
      final response = call('cycleHistory', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': [bleedEntry('e1', '2026-09-01')],
      });
      expect(response['ok'], true);
    });

    test('the bare GMT link name aliases to the database zone', () {
      // GMT has no active `backward` link since tzdata demoted it to a
      // Zone (2024b) — it survives via the generator's retired-link list,
      // and the compiled latest_10y database does not carry it.
      expect(
        tz.timeZoneDatabase.locations.containsKey('GMT'),
        isFalse,
      );
      final response = call('cycleHistory', {
        'today': '2026-09-30',
        'tz': 'GMT',
        'entries': [bleedEntry('e1', '2026-09-01')],
      });
      expect(response['ok'], true);
    });

    test('a malformed date is a named field error', () {
      final response = call('validateDayEntryDate', {
        'date': '30/09/2026',
        'today': '2026-09-30',
      });
      expect(response['ok'], false);
      expect(response['error'], contains('date'));
    });

    test('entries must be an array of objects with ids', () {
      final notArray = call('cycleHistory', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': 'nope',
      });
      expect(notArray['ok'], false);
      final noId = call('cycleHistory', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': [
          {...bleedEntry('e1', '2026-09-01'), 'id': null},
        ],
      });
      expect(noId['ok'], false);
      expect(noId['error'], contains('id'));
    });
  });

  group('IANA legacy link names (issue #1273)', () {
    // The names from the issue plus the bare UTC/GMT: every one is a link
    // name the compiled latest_10y database drops, and a browser reporting
    // it must get a success envelope from every date-math method — the
    // failure mode being fixed was a total one (predict, cycleHistory and
    // insights all resolve `tz` before anything else).
    const legacyNames = [
      'Asia/Calcutta',
      'Europe/Kiev',
      'Asia/Saigon',
      'Asia/Katmandu',
      'UTC',
      'GMT',
    ];

    for (final legacy in legacyNames) {
      test('$legacy resolves instead of erroring', () {
        expect(
          tz.timeZoneDatabase.locations.containsKey(legacy),
          isFalse,
          reason:
              '$legacy is a fixture name because the database drops it; '
              'if the database now carries it, this entry is dead weight '
              'and iana_aliases.dart should be regenerated',
        );
        final response = call('cycleHistory', {
          'today': '2026-09-30',
          'tz': legacy,
          'entries': [bleedEntry('e1', '2026-09-01')],
        });
        expect(response['ok'], true, reason: 'tz: $legacy');
      });
    }

    test('every generated alias resolves to a database zone, and no alias is itself in the database', () {
      // The whole committed table, not just the sampled names: an alias
      // whose target the database lacks would still throw, and an alias the
      // database carries would be shadowed dead weight. Both mean
      // `tool/web_domain/gen_iana_aliases.dart` must be re-run.
      kIanaLegacyAliases.forEach((alias, target) {
        expect(
          tz.timeZoneDatabase.locations.containsKey(target),
          isTrue,
          reason: 'alias "$alias" points at "$target", which the tz '
              'database does not carry',
        );
        expect(
          tz.timeZoneDatabase.locations.containsKey(alias),
          isFalse,
          reason: 'alias "$alias" is itself a database location; the entry '
              'is dead weight — re-run tool/web_domain/gen_iana_aliases.dart',
        );
      });
    });
  });

  group('day-entry codec', () {
    test('export-shaped rows decode with the documented defaults', () {
      final response = call('cycleHistory', {
        'today': '2026-09-30',
        'tz': 'UTC',
        // No profileId on the request: the default 'web' is used; source
        // degrades via the domain's own closed-set normalizer.
        'entries': [
          {
            'id': 'e1',
            'localDate': '2026-09-01',
            'flow': 'heavy',
            'updatedAt': '2026-09-01T12:00:00.000Z',
          },
        ],
      });
      expect(response['ok'], true);
    });

    test('an unrecognised flow degrades instead of throwing', () {
      // FlowLevel.fromDb degrades unknown wire strings; the facade must
      // let that domain behavior through, not invent a stricter one.
      expect(FlowLevel.fromDb('future_flow'), FlowLevel.none);
      expect(DayEntrySource.fromDb('future_source'), DayEntrySource.manual);
    });

    test('a tombstone row is accepted and excluded from episodes', () {
      final response = call('cycleHistory', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': [
          bleedEntry('e1', '2026-09-01'),
          {
            ...bleedEntry('e2', '2026-09-02'),
            'deletedAt': '2026-09-03T00:00:00.000Z',
          },
        ],
      });
      expect(response['ok'], true);
      final data = response['data']! as Map<String, Object?>;
      // One episode from the single live bleed day; the tombstone adds
      // nothing.
      expect(data['episodeCount'], 1);
    });
  });

  group('resolution order', () {
    final disabled = call('predict', {
      'today': '2026-09-30',
      'tz': 'UTC',
      'entries': [bleedEntry('e1', '2026-09-01')],
      'predictionsEnabled': false,
      'lifecycleMode': 'pregnancy',
    });
    test('predictions-disabled wins over lifecycle suppression', () {
      expect((disabled['data']! as Map<String, Object?>)['kind'], 'disabled');
    });

    test('lifecycle suppression wins over birth control', () {
      final response = call('predict', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': [bleedEntry('e1', '2026-09-01')],
        'birthControl': {
          'method': 'pill',
          'startedOn': '2026-08-01',
          'stoppedOn': null,
        },
        'lifecycleMode': 'postpartum',
      });
      final data = response['data']! as Map<String, Object?>;
      expect(data['kind'], 'suppressed');
      expect(data['lifecycleMode'], 'postpartum');
      expect(data['method'], isNull);
    });

    test('a stopped method is not in effect and prediction computes', () {
      final response = call('predict', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': [
          bleedEntry('e1', '2026-08-01'),
          bleedEntry('e2', '2026-08-29'),
          bleedEntry('e3', '2026-09-26'),
          bleedEntry('e4', '2026-09-27'),
        ],
        'birthControl': {
          'method': 'hormonal_iud',
          'startedOn': '2026-08-01',
          'stoppedOn': '2026-09-01',
        },
      });
      final data = response['data']! as Map<String, Object?>;
      expect(data['kind'], 'notEnoughHistory');
    });
  });

  group('buildExport', () {
    Map<String, Object?> exportRequest() => {
      'exportedAt': '2026-09-30T10:00:00.000Z',
      'appVersion': '1.2.3',
      'profiles': [
        {
          'id': 'p1',
          'displayName': 'Ada',
          'isMinor': false,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-09-01T00:00:00.000Z',
          'dayEntries': [bleedEntry('e1', '2026-09-01')],
        },
      ],
    };

    test('builds the app document (schema 15) and is deterministic', () {
      final first = call('buildExport', exportRequest());
      final second = call('buildExport', exportRequest());
      expect(first['ok'], true);
      final data = first['data']! as Map<String, Object?>;
      expect(data['schemaVersion'], 15);
      expect(jsonEncode(first), jsonEncode(second));
    });

    test('missing exportedAt / appVersion are named errors', () {
      final noStamp = exportRequest()..remove('exportedAt');
      expect(call('buildExport', noStamp)['error'], contains('exportedAt'));
      final noVersion = exportRequest()..remove('appVersion');
      expect(call('buildExport', noVersion)['error'], contains('appVersion'));
      final noProfiles = exportRequest()..remove('profiles');
      expect(call('buildExport', noProfiles)['error'], contains('profiles'));
    });
  });

  group('parseInviteLink', () {
    test('parses the custom scheme with kind routing flags', () {
      final response = call('parseInviteLink', {
        'url': 'lunarlog://invite?code=tok&profile=p1&kind=claim',
      });
      expect(response['data'], {
        'code': 'tok',
        'profileId': 'p1',
        'kind': 'claim',
        'isClaim': true,
        'isPrediction': false,
      });
    });

    test('anything that is not a link parses to a null data', () {
      final wrongDomain = call('parseInviteLink', {
        'url': 'https://evil.example/invite?code=tok',
        'linkDomain': 'links.lunarlog.app',
      });
      expect(wrongDomain['ok'], true);
      expect(wrongDomain['data'], isNull);

      final missingCode = call('parseInviteLink', {
        'url': 'lunarlog://invite?profile=p1',
      });
      expect(missingCode['data'], isNull);
    });
  });
}
