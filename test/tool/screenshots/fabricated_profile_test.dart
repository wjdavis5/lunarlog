/// Unit tests for the screenshot tool's fabricated data and its name
/// allowlist (issue #1104): the allowlist is the seed generator's own
/// list (never restated), the tool fails before rendering when a profile
/// name is off that list, and the fabricated dataset is a pure function
/// of the fixed clock — the byte-identity guarantee's data half.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/flow_level.dart';

import '../../../tool/screenshots/fabricated_profile.dart';
import '../../../tool/seed_test_accounts/payload_generator.dart';

void main() {
  group('the name allowlist (#1104)', () {
    test('it IS the seed generator\'s list, imported not restated', () {
      expect(kFabricatedProfileNames, same(kSeedProfileNames));
    });

    test('the generator\'s own fabricated names are all legal', () {
      // Whatever the generator emits today, the screenshot tool accepts.
      requireFabricatedNames(kSeedProfileNames, kFabricatedProfileNames);
    });

    test('the cross-check: a real generated payload only ever names '
        'allowlisted profiles', () {
      // The strongest form of the rule: build a real payload through the
      // real generator (fixed clock, fixed seed) and require every
      // profile display name it carries to be on the screenshot
      // allowlist. A fabricated profile added to the generator keeps
      // this green; a hand-invented name anywhere fails it.
      final payload = generateSeedPayload(SeedSpec(
        months: 12,
        seed: 7,
        clock: () => DateTime.utc(2026, 9, 28, 12),
      ));
      final payloadNames = [
        for (final profile in payload.profiles) profile['display_name'] as String,
      ];
      expect(payloadNames, isNotEmpty);
      requireFabricatedNames(payloadNames, kFabricatedProfileNames);
    });

    test('requireFabricatedNames passes allowlisted names', () {
      requireFabricatedNames(
        ['Maya', 'Riley'],
        kFabricatedProfileNames,
      );
    });

    test('requireFabricatedNames throws on an off-list name — the '
        'issue\'s enforcement line', () {
      FabricatedNameError? caught;
      try {
        requireFabricatedNames(['Maya', 'Alice'], kFabricatedProfileNames);
      } on FabricatedNameError catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: 'Alice is not on the generator\'s '
          'list; the tool must refuse to render her');
      expect(caught!.offenders, ['Alice']);
      expect(caught.toString(), contains('Alice'));
      expect(caught.toString(), contains('Maya'),
          reason: 'the message names the allowlist too');
    });
  });

  group('the fabricated dataset (#1104)', () {
    test('both profiles build, named on the generator\'s list', () {
      final profiles = fabricatedScreenshotProfiles();
      expect(profiles, hasLength(2));
      for (final profile in profiles) {
        expect(
          kFabricatedProfileNames,
          contains(profile.name),
          reason: '${profile.name} must come from the generator',
        );
      }
    });

    test('the adult profile is the high-confidence shape: seven steady '
        'episodes, a filled today', () {
      final maya = fabricatedScreenshotProfiles().first;
      expect(maya.isMinor, isFalse);
      final bleedDates =
          maya.days.where((d) => d.flow == FlowLevel.medium).map((d) => d.date).toSet();
      expect(bleedDates, isNotEmpty);
      // An episode starts on a bleed day whose previous day does not
      // bleed. Seven episodes at a fixed 28-day spacing -> six completed
      // cycles -> the full kAverageWindowCycles window -> `high` (the
      // prediction engine's own rule; this dataset only carries the
      // shape).
      final episodeStarts = bleedDates
          .where((d) => !bleedDates.contains(d.addDays(-1)))
          .toSet();
      expect(episodeStarts, hasLength(7));
      final sortedStarts = episodeStarts.toList()..sort();
      for (var i = 1; i < sortedStarts.length; i++) {
        expect(
          sortedStarts[i].addDays(-28),
          sortedStarts[i - 1],
          reason: 'the episodes are exactly 28 days apart',
        );
      }
      // Today itself is a logged day (the day-sheet screenshot opens on
      // it).
      expect(
        maya.days.any((d) => d.date == kScreenshotToday),
        isTrue,
      );
    });

    test('the teen profile is the learning-tier shape: three completed '
        'cycles of varying length', () {
      final riley = fabricatedScreenshotProfiles().last;
      expect(riley.isMinor, isTrue);
      final bleeds = riley.days.where((d) => d.flow != FlowLevel.notBleeding);
      expect(bleeds, isNotEmpty);
    });

    test('two builds are identical — the data is a pure function of the '
        'fixed clock', () {
      final a = fabricatedScreenshotProfiles();
      final b = fabricatedScreenshotProfiles();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].name, b[i].name);
        expect(a[i].isMinor, b[i].isMinor);
        expect(a[i].birthYear, b[i].birthYear);
        expect(a[i].days.length, b[i].days.length);
        for (var j = 0; j < a[i].days.length; j++) {
          expect(a[i].days[j].date, b[i].days[j].date, reason: 'day $j');
          expect(a[i].days[j].flow, b[i].days[j].flow, reason: 'day $j');
          expect(a[i].days[j].tags, b[i].days[j].tags, reason: 'day $j');
          expect(a[i].days[j].note, b[i].days[j].note, reason: 'day $j');
        }
      }
    });

    test('every date stays inside the fabricated window (bounded past, '
        'no far-future dates)', () {
      for (final profile in fabricatedScreenshotProfiles()) {
        for (final day in profile.days) {
          expect(
            day.date.isAfter(kScreenshotToday.addDays(-400)),
            isTrue,
            reason: '${profile.name}: ${day.date} predates the window',
          );
          expect(
            day.date.isBefore(kScreenshotToday.addDays(8)),
            isTrue,
            reason: '${profile.name}: ${day.date} is unreachably ahead',
          );
        }
      }
    });

    test('notes come from the generator\'s pool, never hand-written', () {
      for (final profile in fabricatedScreenshotProfiles()) {
        for (final day in profile.days) {
          if (day.note != null) {
            expect(kSeedDayNotePool, contains(day.note),
                reason: '${profile.name} ${day.date}: notes must come '
                    'from the generator\'s pool');
          }
        }
      }
    });
  });

  group('the fixed clock (#1104)', () {
    test('is pinned, never DateTime.now()', () {
      expect(kScreenshotToday.year, 2026);
      expect(kScreenshotToday.month, 9);
      expect(kScreenshotToday.day, 28);
    });
  });
}
