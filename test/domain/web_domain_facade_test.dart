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

    test('a tombstone-only predict input computes from zero episodes', () {
      // Issue #1274 audit: predict must behave as if the device had fed it
      // live-only repository rows — a deleted bleed day is not history.
      final response = call('predict', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': [
          {
            ...bleedEntry('e1', '2026-09-01'),
            'deletedAt': '2026-09-02T00:00:00.000Z',
          },
        ],
      });
      expect(response['ok'], true);
      final data = response['data']! as Map<String, Object?>;
      expect(data['kind'], 'notEnoughHistory');
      expect(data['episodeCount'], 0);
    });

    test('a tombstone-only insights input analyzes zero cycles', () {
      // Same audit, insights side: no deleted tag may resurface as a
      // symptom pattern or analyzed cycle.
      final response = call('insights', {
        'today': '2026-09-30',
        'tz': 'UTC',
        'entries': [
          {
            ...bleedEntry('e1', '2026-09-01', pms: true),
            'tags': ['cramps'],
            'deletedAt': '2026-09-02T00:00:00.000Z',
          },
        ],
      });
      expect(response['ok'], true);
      final data = response['data']! as Map<String, Object?>;
      expect(data['analyzedCycleCount'], 0);
      expect(data['hasEnoughData'], false);
      expect(data['symptomPatterns'], <Object?>[]);
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

    test('tombstoned profiles and entries never reach the document', () {
      // Issue #1274: buildAccountExport's contract is tombstone-free
      // inputs (the export row shape has no deletedAt at all), so the
      // facade — the web client's stand-in for the live-only repositories
      // — must filter before it calls. Before the fix this request put a
      // deleted profile (and another profile's deleted entry) into the
      // export as live rows, and restoring the file on a phone recreated
      // the deleted data.
      final request = exportRequest()
        ..['profiles'] = [
          {
            'id': 'p1',
            'displayName': 'Ada',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-09-01T00:00:00.000Z',
            'dayEntries': [
              bleedEntry('e1', '2026-09-01'),
              {
                ...bleedEntry('e2', '2026-09-02'),
                'deletedAt': '2026-09-03T00:00:00.000Z',
              },
            ],
          },
          {
            'id': 'p2',
            'displayName': 'Deleted profile',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-09-01T00:00:00.000Z',
            'deletedAt': '2026-09-10T00:00:00.000Z',
            'dayEntries': [bleedEntry('e3', '2026-09-05')],
          },
        ];
      final response = call('buildExport', request);
      expect(response['ok'], true);
      final data = response['data']! as Map<String, Object?>;
      final profiles = data['profiles']! as List<Object?>;
      // The tombstoned profile p2 is gone entirely — its (live) entry e3
      // goes with it, the way the document nests entries under profiles.
      expect(
        [for (final p in profiles) (p! as Map<String, Object?>)['id']],
        ['p1'],
      );
      // The live profile keeps only its live entry.
      final entries =
          (profiles.single as Map<String, Object?>)['dayEntries']!
              as List<Object?>;
      expect(
        [for (final e in entries) (e! as Map<String, Object?>)['id']],
        ['e1'],
      );
      // And the export shape never carries a tombstone key.
      expect(jsonEncode(data), isNot(contains('deletedAt')));
    });

    test('an all-tombstoned profiles list exports an empty document', () {
      // The request-level non-empty guard is about the request shape, not
      // about how many rows survive the tombstone filter — the device's
      // own builder behaves the same way (an empty live set produces an
      // empty profiles list, not a failure).
      final request = exportRequest()
        ..['profiles'] = [
          {
            'id': 'p1',
            'displayName': 'Ada',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-09-01T00:00:00.000Z',
            'deletedAt': '2026-09-10T00:00:00.000Z',
            'dayEntries': [bleedEntry('e1', '2026-09-01')],
          },
        ];
      final response = call('buildExport', request);
      expect(response['ok'], true);
      final data = response['data']! as Map<String, Object?>;
      expect(data['profiles'], <Object?>[]);
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

  // What the Today log card says about a day. The browser version's card
  // asks here, so the rules are the app's own
  // (lib/domain/logging/today_log.dart); these pin the request decoding and
  // what the response must never carry.
  group('todayLog', () {
    const noteText = 'zebra crossing after the dentist';
    const noteWords = ['zebra', 'crossing', 'dentist'];

    Map<String, Object?> todayEntry({
      String flow = 'none',
      List<String> tags = const [],
      bool pms = false,
      String? note,
      String? deletedAt,
    }) => {
      ...bleedEntry('e-today', '2026-09-30', flow: flow, pms: pms),
      'tags': tags,
      'note': note,
      'deletedAt': deletedAt,
    };

    Map<String, Object?> todayLog(Map<String, Object?> request) {
      final response = call('todayLog', request);
      expect(response['ok'], true, reason: '${response['error']}');
      return response['data']! as Map<String, Object?>;
    }

    const empty = {
      'hasContent': false,
      'flow': null,
      'hasSpotting': false,
      'pms': false,
      'tags': <Object?>[],
      'moreTagCount': 0,
      'bbt': null,
      'weight': null,
      'hasNote': false,
    };

    test('no entry, an absent entry and an empty entry are nothing logged',
        () {
      expect(todayLog({'entry': null}), empty);
      expect(todayLog({}), empty);
      expect(todayLog({'entry': todayEntry()}), empty);
    });

    test('a tombstoned entry says nothing about what it used to hold', () {
      final data = todayLog({
        'entry': todayEntry(
          flow: 'heavy',
          tags: const ['cramps'],
          pms: true,
          note: noteText,
          deletedAt: '2026-09-30T09:00:00.000Z',
        ),
        'observations': [
          {'dayEntryId': 'e-today', 'category': 'spotting'},
          {
            'dayEntryId': 'e-today',
            'category': 'bbt',
            'valueNum': 36.7,
            'unit': 'celsius',
          },
        ],
      });
      expect(data, empty);
    });

    test('the response never carries the note, only that one exists', () {
      final response = handleFacadeCall(
        'todayLog',
        jsonEncode({
          'entry': todayEntry(
            flow: 'medium',
            tags: const ['cramps'],
            note: noteText,
          ),
        }),
      );
      final data = (jsonDecode(response) as Map<String, Object?>)['data']!
          as Map<String, Object?>;
      expect(data['hasNote'], true);
      expect(data.containsKey('note'), isFalse);
      for (final word in noteWords) {
        expect(response, isNot(contains(word)));
      }
    });

    test('a note of only spaces is not a note', () {
      expect(todayLog({'entry': todayEntry(note: '   ')}), empty);
    });

    test('the response names tags by label and never by code', () {
      final response = handleFacadeCall(
        'todayLog',
        jsonEncode({
          'entry': todayEntry(
            tags: const [
              'back_pain',
              'unprotected_sex',
              'pregnancy_positive',
              'some_new_code',
            ],
          ),
        }),
      );
      final data = (jsonDecode(response) as Map<String, Object?>)['data']!
          as Map<String, Object?>;
      expect(data['tags'], ['Back pain']);
      expect(data['moreTagCount'], 3);
      for (final hidden in [
        'back_pain',
        'unprotected_sex',
        'Unprotected',
        'pregnancy',
        'Pregnancy',
        'some_new_code',
      ]) {
        expect(response, isNot(contains(hidden)));
      }
    });

    test('at most six labels come back; the rest are counted', () {
      final data = todayLog({
        'entry': todayEntry(
          tags: const [
            'cramps',
            'headache',
            'back_pain',
            'fatigue',
            'acne',
            'migraine',
            'anxious',
            'protected_sex',
          ],
        ),
      });
      expect(data['tags'], [
        'Cramps',
        'Headache',
        'Back pain',
        'Fatigue',
        'Acne',
        'Migraine',
      ]);
      expect(data['moreTagCount'], 2);
    });

    test('a registry row names its tag; a deleted row names nothing', () {
      final data = todayLog({
        'entry': todayEntry(tags: const ['back_cracking', 'gone_tag']),
        'customTags': [
          {'code': 'back_cracking', 'displayName': 'Back cracking'},
          {
            'code': 'gone_tag',
            'displayName': 'Gone',
            'deletedAt': '2026-09-01T00:00:00.000Z',
          },
        ],
      });
      expect(data['tags'], ['Back cracking']);
      expect(data['moreTagCount'], 1);
    });

    test('bleed wins over spotting, and spotting over "not bleeding"', () {
      const spotting = [
        {'dayEntryId': 'e-today', 'category': 'spotting'},
      ];
      final bleed = todayLog({
        'entry': todayEntry(flow: 'heavy'),
        'observations': spotting,
      });
      expect(bleed['flow'], 'heavy');
      expect(bleed['hasSpotting'], true);

      final spotted = todayLog({
        'entry': todayEntry(flow: 'not_bleeding'),
        'observations': spotting,
      });
      expect(spotted['flow'], 'spotting');
      expect(spotted['hasSpotting'], true);

      final dry = todayLog({'entry': todayEntry(flow: 'not_bleeding')});
      expect(dry['flow'], 'not_bleeding');
      expect(dry['hasSpotting'], false);
    });

    test('a row that stores spotting as its flow level reads as spotting, '
        'as the device reads it', () {
      final data = todayLog({'entry': todayEntry(flow: 'spotting')});
      expect(data['hasContent'], true);
      expect(data['flow'], 'spotting');
      expect(data['hasSpotting'], true);
    });

    test('an observation that is deleted, or attached to another entry, '
        'is not this day\'s', () {
      final data = todayLog({
        'entry': todayEntry(),
        'observations': [
          {
            'dayEntryId': 'e-today',
            'category': 'spotting',
            'deletedAt': '2026-09-30T09:00:00.000Z',
          },
          {'dayEntryId': 'e-yesterday', 'category': 'spotting'},
          {
            'dayEntryId': 'e-yesterday',
            'category': 'weight',
            'valueNum': 60,
            'unit': 'kg',
          },
        ],
      });
      expect(data, empty);
    });

    test('a reading another source wrote is not the day\'s reading', () {
      final data = todayLog({
        'entry': todayEntry(),
        'observations': [
          {
            'dayEntryId': 'e-today',
            'category': 'bbt',
            'valueNum': 36.5,
            'unit': 'celsius',
            'source': 'wearable',
          },
        ],
      });
      expect(data, empty);
    });

    test('a reading is answered in the profile\'s units, whatever it was '
        'stored in', () {
      final data = todayLog({
        'entry': todayEntry(),
        'observations': [
          {
            'dayEntryId': 'e-today',
            'category': 'bbt',
            'valueNum': 37,
            'unit': 'celsius',
          },
          {
            'dayEntryId': 'e-today',
            'category': 'weight',
            'valueNum': 50,
            'unit': 'kg',
          },
        ],
        'bbtUnit': 'fahrenheit',
        'weightUnit': 'lb',
      });
      final bbt = data['bbt']! as Map<String, Object?>;
      final weight = data['weight']! as Map<String, Object?>;
      expect(bbt['unit'], 'fahrenheit');
      expect(bbt['value'], closeTo(98.6, 1e-9));
      expect(weight['unit'], 'lb');
      expect(weight['value'], closeTo(110.2311, 1e-4));
    });

    test('with no units named, a reading comes back in Celsius and '
        'kilograms', () {
      final data = todayLog({
        'entry': todayEntry(),
        'observations': [
          {
            'dayEntryId': 'e-today',
            'category': 'bbt',
            'valueNum': 98.6,
            'unit': 'fahrenheit',
          },
          {
            'dayEntryId': 'e-today',
            'category': 'weight',
            'valueNum': 61,
            'unit': 'kg',
          },
        ],
      });
      final bbt = data['bbt']! as Map<String, Object?>;
      expect(bbt['unit'], 'celsius');
      expect(bbt['value'], closeTo(37, 1e-9));
      expect(data['weight'], {'value': 61, 'unit': 'kg'});
    });

    test('malformed inputs are error envelopes, not throws', () {
      expect(call('todayLog', {'entry': 'nope'})['error'], contains('entry'));
      expect(
        call('todayLog', {
          'entry': todayEntry(flow: 'medium'),
          'observations': 'nope',
        })['error'],
        contains('observations'),
      );
      expect(
        call('todayLog', {
          'entry': todayEntry(flow: 'medium'),
          'observations': ['nope'],
        })['error'],
        contains('observations[0]'),
      );
      expect(
        call('todayLog', {
          'entry': todayEntry(flow: 'medium'),
          'observations': [
            {'dayEntryId': 'e-today', 'category': 'bbt', 'valueNum': 'warm'},
          ],
        })['error'],
        contains('valueNum'),
      );
      expect(
        call('todayLog', {
          'entry': todayEntry(tags: const ['cramps']),
          'customTags': 'nope',
        })['error'],
        contains('customTags'),
      );
      expect(
        call('todayLog', {
          'entry': todayEntry(tags: const ['cramps']),
          'customTags': ['nope'],
        })['error'],
        contains('customTags[0]'),
      );
    });

    test('a row missing what the log reads is skipped, not an error', () {
      final data = todayLog({
        'entry': todayEntry(tags: const ['back_cracking']),
        'observations': [
          {'dayEntryId': 'e-today', 'category': null},
        ],
        'customTags': [
          {'code': 'back_cracking'},
          {'displayName': 'No code'},
        ],
      });
      expect(data['tags'], <Object?>[]);
      expect(data['moreTagCount'], 1);
      expect(data['hasSpotting'], false);
    });
  });
}
