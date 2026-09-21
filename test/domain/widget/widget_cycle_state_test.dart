/// Unit tests for the home-screen widget's render-state derivation and
/// boundary payload (issue #141): what each prediction kind renders as,
/// and — the privacy regression guard — that the payload crossing the
/// app-group boundary is *exactly* the documented six-key set, never more.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/widget/widget_cycle_state.dart';

void main() {
  group('WidgetCycleState.fromPrediction', () {
    test('NotEnoughHistory renders the neutral no-data state', () {
      final state = WidgetCycleState.fromPrediction(
        const NotEnoughHistory(
          episodeCount: 0,
          completedCycleCount: 0,
          validCycleCount: 0,
          usableCycleCount: 0,
        ),
        canQuickLog: true,
      );
      expect(state.kind, WidgetCycleStateKind.noData);
      expect(state.canQuickLog, isTrue,
          reason: 'the role gate is independent of the history state');
    });

    test('ActivePrediction carries the day count and the estimate', () {
      final state = WidgetCycleState.fromPrediction(
        _activePrediction(cycleDay: 14, daysUntilNextStart: 7),
        canQuickLog: true,
      );
      expect(state.kind, WidgetCycleStateKind.cycleDay);
      expect(state.cycleDay, 14);
      expect(state.daysUntilNext, 7);
      expect(state.canQuickLog, isTrue);
    });

    test('an in-progress episode still renders a plain day count', () {
      // The discreet default: during a logged bleed the widget keeps
      // counting days — it never renders the word "period".
      final state = WidgetCycleState.fromPrediction(
        _activePrediction(cycleDay: 3, daysUntilNextStart: 25),
        canQuickLog: true,
      );
      expect(state.kind, WidgetCycleStateKind.cycleDay);
      expect(state.cycleDay, 3);
    });

    test('PredictionsSuppressed renders the dash and keeps the role gate',
        () {
      final state = WidgetCycleState.fromPrediction(
        const PredictionsSuppressed(lifecycleMode: LifecycleMode.pregnancy),
        canQuickLog: true,
      );
      expect(state.kind, WidgetCycleStateKind.suppressed);
      expect(state.canQuickLog, isTrue);
    });

    test('equality follows all four fields (and hashCode agrees)', () {
      final a = WidgetCycleState(
        kind: WidgetCycleStateKind.cycleDay,
        cycleDay: 14,
        daysUntilNext: 7,
        canQuickLog: true,
      );
      expect(a, a, reason: 'identical');
      expect(
        a,
        WidgetCycleState(
          kind: WidgetCycleStateKind.cycleDay,
          cycleDay: 14,
          daysUntilNext: 7,
          canQuickLog: true,
        ),
      );
      expect(a.hashCode,
          WidgetCycleState(
            kind: WidgetCycleStateKind.cycleDay,
            cycleDay: 14,
            daysUntilNext: 7,
            canQuickLog: true,
          ).hashCode);
      for (final different in [
        const WidgetCycleState(
          kind: WidgetCycleStateKind.cycleDay,
          cycleDay: 15,
          daysUntilNext: 7,
          canQuickLog: true,
        ),
        WidgetCycleState(
          kind: WidgetCycleStateKind.cycleDay,
          cycleDay: 14,
          daysUntilNext: 8,
          canQuickLog: true,
        ),
        WidgetCycleState(
          kind: WidgetCycleStateKind.cycleDay,
          cycleDay: 14,
          daysUntilNext: 7,
          canQuickLog: false,
        ),
        WidgetCycleState(
          kind: WidgetCycleStateKind.off,
          cycleDay: 14,
          daysUntilNext: 7,
          canQuickLog: true,
        ),
      ]) {
        expect(a == different, isFalse,
            reason: 'must differ: $different');
      }
      expect(a == Object(), isFalse);
    });

    test('PredictionsDisabled renders the dash and keeps the role gate',
        () {
      final state = WidgetCycleState.fromPrediction(
        const PredictionsDisabled(),
        canQuickLog: true,
      );
      expect(state.kind, WidgetCycleStateKind.off);
      expect(state.canQuickLog, isTrue);
    });
  });

  group('WidgetCycleStatePayload.encode — the app-group boundary', () {
    final asOf = LocalDate(2026, 9, 20);

    test('the live-cycle payload is exactly the documented six keys', () {
      final payload = WidgetCycleStatePayload.encode(
        state: WidgetCycleState.fromPrediction(
          _activePrediction(cycleDay: 14, daysUntilNextStart: 7),
          canQuickLog: true,
        ),
        profileId: 'PROFILE1',
        asOf: asOf,
      );
      // The privacy regression guard: the key set is exactly the set the
      // boundary documentation pins. A new key added without its own
      // documented justification and privacy review fails here.
      expect(
        payload.keys.toSet(),
        equals({
          WidgetCycleStatePayload.keyState,
          WidgetCycleStatePayload.keyCycleDay,
          WidgetCycleStatePayload.keyDaysUntilNext,
          WidgetCycleStatePayload.keyCanQuickLog,
          WidgetCycleStatePayload.keyProfileId,
          WidgetCycleStatePayload.keyAsOf,
        }),
      );
      expect(payload[WidgetCycleStatePayload.keyState], 'day');
      expect(payload[WidgetCycleStatePayload.keyCycleDay], '14');
      expect(payload[WidgetCycleStatePayload.keyDaysUntilNext], '7');
      expect(payload[WidgetCycleStatePayload.keyCanQuickLog], '1');
      expect(payload[WidgetCycleStatePayload.keyProfileId], 'PROFILE1');
      expect(payload[WidgetCycleStatePayload.keyAsOf], '2026-09-20');
    });

    test('a viewer payload carries no quick-log flag', () {
      final payload = WidgetCycleStatePayload.encode(
        state: WidgetCycleState.fromPrediction(
          _activePrediction(cycleDay: 14, daysUntilNextStart: 7),
          canQuickLog: false,
        ),
        profileId: 'PROFILE1',
        asOf: asOf,
      );
      expect(payload[WidgetCycleStatePayload.keyCanQuickLog], '0');
    });

    test('the no-data payload omits the numeric keys entirely', () {
      final payload = WidgetCycleStatePayload.encode(
        state: const WidgetCycleState(kind: WidgetCycleStateKind.noData),
        profileId: 'PROFILE1',
        asOf: asOf,
      );
      expect(payload.keys.toSet(), equals({
        WidgetCycleStatePayload.keyState,
        WidgetCycleStatePayload.keyCanQuickLog,
        WidgetCycleStatePayload.keyProfileId,
        WidgetCycleStatePayload.keyAsOf,
      }));
      expect(payload[WidgetCycleStatePayload.keyState], 'no_data');
    });

    test('suppressed and off are distinct states, both dash-rendered', () {
      for (final entry in [
        (
          WidgetCycleStateKind.suppressed,
          WidgetCycleState.fromPrediction(
            const PredictionsSuppressed(lifecycleMode: LifecycleMode.pregnancy),
            canQuickLog: true,
          )
        ),
        (
          WidgetCycleStateKind.off,
          WidgetCycleState.fromPrediction(
            const PredictionsDisabled(),
            canQuickLog: true,
          )
        ),
      ]) {
        final payload = WidgetCycleStatePayload.encode(
          state: entry.$2,
          profileId: 'PROFILE1',
          asOf: asOf,
        );
        expect(
          payload[WidgetCycleStatePayload.keyState],
          switch (entry.$1) {
            WidgetCycleStateKind.suppressed => 'suppressed',
            _ => 'off',
          },
        );
      }
    });
  });
}

/// A minimal [ActivePrediction] — every field the widget derivation reads,
/// everything else at its defaults.
ActivePrediction _activePrediction({
  required int cycleDay,
  required int daysUntilNextStart,
}) {
  final today = LocalDate(2026, 9, 20);
  final lastStart = today.addDays(-(cycleDay - 1));
  return ActivePrediction(
    today: today,
    lastEpisodeStart: lastStart,
    estimatedNextStart: today.addDays(daysUntilNextStart),
    originalEstimatedNextStart: today.addDays(daysUntilNextStart),
    averagedCycleLengths: const [28, 28, 28],
    meanCycleLengthDays: 28,
    cycleDay: cycleDay,
    duringEpisode: false,
    completedCycleCount: 3,
    validCycleCount: 3,
  );
}
