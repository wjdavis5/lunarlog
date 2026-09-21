/// Pure-layer tests for the household view's per-profile signals (issue
/// #803): the timing signal's prediction/framing variants, the silence
/// gate (history + threshold + timing suppression), the threshold mapping
/// from the profile's local reminder preferences, the unread-changes
/// count, and the localized copy built from the ARB.
///
/// No widget tree, no streams: exactly the inputs the row widget already
/// holds (a [CyclePrediction], entry dates, a feed snapshot's baseline and
/// items) against `lookupAppLocalizations` — the same shape
/// `test/ui/components/profile_card_test.dart` uses for `profileCycleStatus`.
library;

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/activity/activity_feed.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/household_signals.dart';

/// Fixed "today" so every day count is deterministic.
final LocalDate kToday = LocalDate(2026, 9, 20);

AppLocalizations get _l10n => lookupAppLocalizations(const Locale('en'));

ActivePrediction _active({
  int cycleDay = 14,
  bool duringEpisode = false,
  int daysPastEstimate = 0,
  bool unusuallyLongCycle = false,
  bool staleHistory = false,
}) {
  final lastStart = kToday.addDays(-(cycleDay - 1));
  final originalEstimate = kToday.addDays(-daysPastEstimate);
  return ActivePrediction(
    today: kToday,
    lastEpisodeStart: lastStart,
    // The rolled estimate sits within the grace window of today whenever
    // the raw estimate is past it (the engine's own forward-roll), so the
    // two never disagree about the late state the row renders.
    estimatedNextStart: daysPastEstimate > 2
        ? kToday.addDays(1)
        : originalEstimate,
    originalEstimatedNextStart: originalEstimate,
    averagedCycleLengths: const [28, 28, 28],
    meanCycleLengthDays: 28,
    cycleDay: cycleDay,
    duringEpisode: duringEpisode,
    completedCycleCount: 3,
    validCycleCount: 3,
    unusuallyLongCycle: unusuallyLongCycle,
    staleHistory: staleHistory,
  );
}

DayEntry _entry(LocalDate date) => DayEntry(
  id: 'e-${date.iso}',
  profileId: 'p1',
  localDate: date,
  tz: 'UTC',
  flow: FlowLevel.medium,
  updatedAt: DateTime.utc(2026, 9, 1),
);

ActivityItem _item(String id, DateTime occurredAt) =>
    ActivityItem(id: id, kind: ActivityKind.logged, occurredAt: occurredAt);

void main() {
  group('householdTimingSignal (pure, issue #803)', () {
    test('null prediction (first emission not landed) carries no signal', () {
      expect(
        householdTimingSignal(prediction: null, irregularFraming: false),
        isNull,
      );
    });

    test('no-history / suppressed / disabled predictions carry no signal', () {
      const notEnough = NotEnoughHistory(
        episodeCount: 1,
        completedCycleCount: 1,
        validCycleCount: 0,
        usableCycleCount: 0,
      );
      expect(
        householdTimingSignal(prediction: notEnough, irregularFraming: false),
        isNull,
      );
      expect(
        householdTimingSignal(
          prediction: const PredictionsSuppressed(
            lifecycleMode: LifecycleMode.pregnancy,
          ),
          irregularFraming: false,
        ),
        isNull,
      );
      expect(
        householdTimingSignal(
          prediction: const PredictionsDisabled(),
          irregularFraming: false,
        ),
        isNull,
      );
    });

    test('a profile mid-episode carries no timing line (the row already '
        'reads "Period, day N")', () {
      expect(
        householdTimingSignal(
          prediction: _active(cycleDay: 2, duringEpisode: true),
          irregularFraming: false,
        ),
        isNull,
      );
    });

    test('an estimate inside the upcoming window reads "expected"', () {
      // Cycle day 26 of a 28-day mean: due in 2 days.
      final signal = householdTimingSignal(
        prediction: _active(cycleDay: 26, daysPastEstimate: -2),
        irregularFraming: false,
      );
      expect(signal, isA<HouseholdTimingExpected>());
      expect(signal!.days, 2);
    });

    test('the estimate falling on today reads "expected today"', () {
      final signal = householdTimingSignal(
        prediction: _active(cycleDay: 28, daysPastEstimate: 0),
        irregularFraming: false,
      );
      expect(signal, isA<HouseholdTimingExpected>());
      expect(signal!.days, 0);
    });

    test('an estimate outside the window carries no timing line', () {
      // Cycle day 10 of a 28-day mean: 18 days out — the row's plain
      // "Cycle day 10" is the honest summary.
      expect(
        householdTimingSignal(
          prediction: _active(cycleDay: 10, daysPastEstimate: -18),
          irregularFraming: false,
        ),
        isNull,
      );
    });

    test('a late unframed profile derives a late timing signal', () {
      final signal = householdTimingSignal(
        prediction: _active(cycleDay: 32, daysPastEstimate: 4),
        irregularFraming: false,
      );
      expect(signal, isA<HouseholdTimingLate>());
      expect(signal!.days, 4);
    });

    test('AC: an irregular-mode profile never reads "late" — the framing '
        'renders the quiet factual line instead (#853)', () {
      final signal = householdTimingSignal(
        prediction: _active(cycleDay: 32, daysPastEstimate: 4),
        irregularFraming: true,
      );
      expect(signal, isA<HouseholdTimingOpen>());
      expect(signal!.days, 31, reason: 'days since the last period started');
    });

    test('the composed framing (teen until high confidence) is the '
        'caller\'s resolved flag, not re-derived here', () {
      // The same prediction, framed: no "late" — and no precise "expected
      // in N days" either (the false precision the framing avoids).
      final lateFramed = householdTimingSignal(
        prediction: _active(cycleDay: 32, daysPastEstimate: 4),
        irregularFraming: true,
      );
      expect(lateFramed, isA<HouseholdTimingOpen>());
      final upcomingFramed = householdTimingSignal(
        prediction: _active(cycleDay: 26, daysPastEstimate: -2),
        irregularFraming: true,
      );
      expect(upcomingFramed, isNull);
    });

    test('a stale history renders the soft line in both framings (#859: '
        'the day count is too old to call late)', () {
      for (final framing in [false, true]) {
        final signal = householdTimingSignal(
          prediction: _active(
            cycleDay: 90,
            daysPastEstimate: 60,
            staleHistory: true,
          ),
          irregularFraming: framing,
        );
        expect(signal, isA<HouseholdTimingOpen>(), reason: 'framing $framing');
      }
    });

    test('an unusually long open cycle whose (long-mean) estimate is still '
        'ahead reads soft even unframed — the #221 folded state without a '
        'late count', () {
      final signal = householdTimingSignal(
        prediction: _active(
          cycleDay: 61,
          daysPastEstimate: -29,
          unusuallyLongCycle: true,
        ),
        irregularFraming: false,
      );
      expect(signal, isA<HouseholdTimingOpen>());
    });

    test('an open cycle that has not yet crossed the grace window carries '
        'no signal at all', () {
      expect(
        householdTimingSignal(
          prediction: _active(cycleDay: 30, daysPastEstimate: 2),
          irregularFraming: false,
        ),
        isNull,
      );
    });
  });

  group('householdTimingCopy (ARB)', () {
    test('every variant reads from the ARB with a pluralized count', () {
      expect(
        householdTimingCopy(const HouseholdTimingExpected(0), _l10n),
        'Period expected today',
      );
      expect(
        householdTimingCopy(const HouseholdTimingExpected(3), _l10n),
        'Period expected in 3 days',
      );
      expect(
        householdTimingCopy(const HouseholdTimingExpected(1), _l10n),
        'Period expected in 1 day',
      );
      expect(
        householdTimingCopy(const HouseholdTimingLate(4), _l10n),
        '4 days past the estimate',
      );
      expect(
        householdTimingCopy(const HouseholdTimingLate(1), _l10n),
        '1 day past the estimate',
      );
      expect(
        householdTimingCopy(const HouseholdTimingOpen(12), _l10n),
        'Last period 12 days ago',
      );
    });
  });

  group('householdSilenceThresholdDays (reminder-preference mapping)', () {
    test('a profile with no stored config falls back to the default', () {
      expect(householdSilenceThresholdDays(null), kHouseholdSilenceDefaultDays);
    });

    test('a disabled log nudge falls back to the default (the signal stays '
        'local even when the operator never configured reminders)', () {
      const off = ReminderTypeConfig(
        enabled: false,
        timeOfDayMinutes: kDefaultReminderTimeMinutes,
      );
      expect(householdSilenceThresholdDays(off), kHouseholdSilenceDefaultDays);
    });

    test('the cadence maps to its own length (two days for a daily nudge)', () {
      ReminderTypeConfig cadence(ReminderCadence c) => ReminderTypeConfig(
        enabled: true,
        timeOfDayMinutes: kDefaultReminderTimeMinutes,
        cadence: c,
      );
      expect(householdSilenceThresholdDays(cadence(ReminderCadence.daily)), 2);
      expect(householdSilenceThresholdDays(cadence(ReminderCadence.weekly)), 7);
      expect(
        householdSilenceThresholdDays(cadence(ReminderCadence.fortnightly)),
        14,
      );
      expect(
        householdSilenceThresholdDays(cadence(ReminderCadence.monthly)),
        30,
      );
    });
  });

  group('daysSinceLastLog (pure)', () {
    test('no entries: null — a fresh profile is never "silent"', () {
      expect(daysSinceLastLog(const [], kToday), isNull);
    });

    test('whole civil days from the latest logged date', () {
      final entries = [_entry(kToday.addDays(-12)), _entry(kToday.addDays(-3))];
      expect(daysSinceLastLog(entries, kToday), 3);
    });

    test('logged today reads zero', () {
      expect(daysSinceLastLog([_entry(kToday)], kToday), 0);
    });
  });

  group('householdSilenceLine (gate + ARB)', () {
    test('no history renders nothing', () {
      expect(
        householdSilenceLine(
          daysSinceLastLog: null,
          thresholdDays: 3,
          timingSignalVisible: false,
          l10n: _l10n,
        ),
        isNull,
      );
    });

    test('a quiet stretch below the threshold renders nothing', () {
      expect(
        householdSilenceLine(
          daysSinceLastLog: 2,
          thresholdDays: 3,
          timingSignalVisible: false,
          l10n: _l10n,
        ),
        isNull,
      );
    });

    test('at or past the threshold reads "Nothing logged for N days"', () {
      expect(
        householdSilenceLine(
          daysSinceLastLog: 12,
          thresholdDays: 3,
          timingSignalVisible: false,
          l10n: _l10n,
        ),
        'Nothing logged for 12 days',
      );
      expect(
        householdSilenceLine(
          daysSinceLastLog: 1,
          thresholdDays: 1,
          timingSignalVisible: false,
          l10n: _l10n,
        ),
        'Nothing logged for 1 day',
      );
    });

    test('suppressed while a timing signal shows (the late/open count '
        'already says nobody has logged)', () {
      expect(
        householdSilenceLine(
          daysSinceLastLog: 12,
          thresholdDays: 3,
          timingSignalVisible: true,
          l10n: _l10n,
        ),
        isNull,
      );
    });
  });

  group('householdChangesLine (feed unread count)', () {
    test('never-opened feed: no baseline, never "new" (isActivityNew\'s '
        'own discipline)', () {
      final baseline = DateTime.utc(2026, 9, 18);
      expect(
        householdChangesLine(
          lastSeen: null,
          items: [_item('a', baseline)],
          l10n: _l10n,
        ),
        isNull,
      );
    });

    test('counts only the rows newer than the last-seen baseline', () {
      final baseline = DateTime.utc(2026, 9, 18);
      final count = householdChangesLine(
        lastSeen: baseline,
        items: [
          _item('old', DateTime.utc(2026, 9, 17)),
          _item('boundary', baseline),
          _item('new-1', DateTime.utc(2026, 9, 19)),
          _item('new-2', DateTime.utc(2026, 9, 20)),
        ],
        l10n: _l10n,
      );
      expect(count, '2 changes since you last looked');
    });

    test('a row at the exact baseline instant is not new (isAfter)', () {
      final baseline = DateTime.utc(2026, 9, 18);
      expect(
        householdChangesLine(
          lastSeen: baseline,
          items: [_item('boundary', baseline)],
          l10n: _l10n,
        ),
        isNull,
      );
    });

    test('singular reads "1 change"', () {
      final baseline = DateTime.utc(2026, 9, 18);
      expect(
        householdChangesLine(
          lastSeen: baseline,
          items: [_item('new', DateTime.utc(2026, 9, 19))],
          l10n: _l10n,
        ),
        '1 change since you last looked',
      );
    });
  });
}
