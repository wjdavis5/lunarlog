/// Widget tests for the household row's changes line and the history dot
/// agreeing on unshared profiles (issue #1236, the #1216/#1218 defect class
/// on the picker surface).
///
/// The picker's "N changes since you last looked" line
/// ([HouseholdRowSignals]) and the feed entry-point's new-activity dot
/// ([ActivityFeedButton]) read the same snapshot: `hasNewItems` gated the
/// dot on `isShared` (issue #1216) while the line counted the raw items
/// with no gate, so an unshared profile earned a picker count the feed
/// never lists — and the visit itself (which stamps last-seen before the
/// `!isShared` early return even renders "Just you for now") silently
/// cleared it. These tests pump both surfaces on one repository stream and
/// pin the agreement in both states: unshared (quiet everywhere, including
/// after a visit) and shared (both announce, both clear together on the
/// visit's re-stamp).
library;

import 'dart:async' show StreamController, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/activity/activity_feed.dart';
import 'package:lunarlog/domain/activity/activity_feed_snapshot.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/activity_feed_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/household_signals.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';

/// The device-local baseline: the operator last opened the feed here, so
/// [kFreshItem] (logged after it) is unread until the next visit stamps
/// past it.
final DateTime kBaseline = DateTime.utc(2026, 9, 18);

final DateTime kFreshAt = DateTime.utc(2026, 9, 19, 10);

/// What a feed visit stamps (`activity_feed_screen.dart`'s
/// `_onFirstSnapshot` schedules `markSeen` before its `!isShared` early
/// return, so an unshared visit stamps this too — the behavior #1236 does
/// not change; the line just stops promising what that visit erases).
final DateTime kVisitStamp = DateTime.utc(2026, 9, 21, 12);

ActivityItem _freshItem() => ActivityItem(
  id: 'entry:e1',
  kind: ActivityKind.logged,
  occurredAt: kFreshAt,
);

ActivityFeedSnapshot _snapshot({required bool isShared, DateTime? lastSeen}) =>
    ActivityFeedSnapshot(
      items: [_freshItem()],
      guardians: const [],
      lastSeen: lastSeen,
      isShared: isShared,
    );

/// Emits the caller-mutated snapshot to every watcher, first value on
/// subscribe, re-emitting on [markSeen] exactly the way the Drift
/// repository's settings-store stamp does. Records `markSeen` calls so a
/// test can prove the visit really happened.
class _FakeFeedRepository implements ActivityFeedRepository {
  _FakeFeedRepository(this._snapshot);

  ActivityFeedSnapshot _snapshot;
  final _controller = StreamController<ActivityFeedSnapshot>.broadcast();
  int markSeenCalls = 0;

  @override
  Stream<ActivityFeedSnapshot> watch(String profileId) async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  @override
  Future<void> markSeen(String profileId) {
    markSeenCalls += 1;
    _snapshot = ActivityFeedSnapshot(
      items: _snapshot.items,
      guardians: _snapshot.guardians,
      lastSeen: kVisitStamp,
      isShared: _snapshot.isShared,
    );
    _controller.add(_snapshot);
    return Future.value();
  }

  void dispose() => unawaited(_controller.close());
}

/// An empty entries stream (the row's silence signal has nothing to read —
/// `daysSinceLastLog` stays null, so the changes line is the only line
/// either state could render); everything else is unreachable here.
class _EmptyEntriesRepository implements DayEntriesRepository {
  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// No timing line: the household row's other signals stay quiet, so every
/// assertion below is about the changes line alone.
class _NoTimingPredictionService extends CyclePredictionService {
  _NoTimingPredictionService(super.entries);

  @override
  Stream<CyclePrediction> watch(
    String profileId, {
    LocalDate Function()? today,
  }) => Stream.value(
    const NotEnoughHistory(
      episodeCount: 1,
      completedCycleCount: 1,
      validCycleCount: 0,
      usableCycleCount: 0,
    ),
  );
}

Profile _profile() => Profile(
  id: 'p1',
  displayName: 'Maya',
  isMinor: true,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// The picker row and the feed entry point on one repository stream —
/// exactly the two surfaces the issue found disagreeing.
Widget _pickerRowAndFeedButton(ActivityFeedRepository feed) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => ListView(
        children: [
          HouseholdRowSignals(
            profile: _profile(),
            predictionService: _NoTimingPredictionService(
              _EmptyEntriesRepository(),
            ),
            feedRepository: feed,
            dayEntriesRepository: _EmptyEntriesRepository(),
          ),
          ActivityFeedButton(profile: _profile(), repository: feed),
        ],
      ),
    ),
  ),
);

Future<void> _pump(WidgetTester tester, ActivityFeedRepository feed) async {
  await tester.pumpWidget(_pickerRowAndFeedButton(feed));
  await tester.pump();
}

void main() {
  testWidgets(
    'AC (#1236): an unshared profile renders no changes line and no dot, '
    'and the feed visit that stamps last-seen clears nothing because '
    'nothing ever accrued',
    (tester) async {
      final feed = _FakeFeedRepository(
        _snapshot(isShared: false, lastSeen: kBaseline),
      );
      addTearDown(feed.dispose);
      await _pump(tester, feed);

      expect(
        find.byKey(const ValueKey('household-changes-p1')),
        findsNothing,
        reason:
            'the single-guardian feed never lists these rows — the '
            'picker must not promise a count of them',
      );
      expect(
        find.byKey(const ValueKey('activity-feed-button-new')),
        findsNothing,
        reason: 'the dot has been gated since #1216',
      );

      // The visit: markSeen stamps past the fresh item (the same stamp the
      // real screen schedules on its first snapshot) and the row still
      // promises nothing — line and dot agree before and after.
      await feed.markSeen('p1');
      await tester.pump();

      expect(feed.markSeenCalls, 1, reason: 'the visit really stamped');
      expect(find.byKey(const ValueKey('household-changes-p1')), findsNothing);
      expect(
        find.byKey(const ValueKey('activity-feed-button-new')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'the shared control: line and dot both announce the same unread row '
    'and both clear together on the visit\'s re-stamp',
    (tester) async {
      final feed = _FakeFeedRepository(
        _snapshot(isShared: true, lastSeen: kBaseline),
      );
      addTearDown(feed.dispose);
      await _pump(tester, feed);

      expect(find.text('1 change since you last looked'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('activity-feed-button-new')),
        findsOneWidget,
      );

      await feed.markSeen('p1');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('household-changes-p1')),
        findsNothing,
        reason: 'the visit advanced the baseline past the row',
      );
      expect(
        find.byKey(const ValueKey('activity-feed-button-new')),
        findsNothing,
        reason:
            'the dot clears on the same stamp — the two surfaces '
            'never disagree',
      );
    },
  );
}
