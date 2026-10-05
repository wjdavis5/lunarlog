/// Issue #1489: [TodayLogWatchMixin], the subscription the Today log card
/// and the floating button's label share — what it subscribes to, what it
/// hands back, and that it lets go: an answer that has been overtaken or
/// that arrives after the widget has gone is dropped, and the subscription
/// is cancelled on dispose and on every re-watch.
///
/// Driven by hand-fed fakes so the order of events is the test's to choose;
/// the same watch over the real database is covered by
/// `test/ui/components/today_log_fab_test.dart` and
/// `test/ui/overview/today_log_overview_test.dart`.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/logging/today_log.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/ui/logging/today_log_watch.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);
final DateTime kNow = DateTime.utc(2026, 8, 30, 12);

DayEntry entryOn(
  LocalDate date, {
  String id = 'e1',
  List<String> tags = const ['cramps'],
  DateTime? deletedAt,
}) =>
    DayEntry(
      id: id,
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.none,
      tags: tags,
      updatedAt: kNow,
      deletedAt: deletedAt,
    );

Observation spottingFor(String dayEntryId) => Observation(
      id: 'o-$dayEntryId',
      dayEntryId: dayEntryId,
      profileId: 'p1',
      localDate: kToday,
      tz: 'UTC',
      category: ObservationCategory.spotting,
      code: 'spotting',
      updatedAt: kNow,
    );

/// An entries seam whose one stream per watch the test feeds by hand.
class _HandFedEntries implements DayEntriesRepository {
  final List<({String profileId, LocalDate? from, LocalDate? to})> watches =
      [];
  final List<StreamController<List<DayEntry>>> controllers = [];

  StreamController<List<DayEntry>> get latest => controllers.last;

  /// Whether the stream handed out by the [watch]th call still has its
  /// listener.
  bool isListenedTo(int watch) => controllers[watch].hasListener;

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) {
    watches.add((profileId: profileId, from: from, to: to));
    final controller = StreamController<List<DayEntry>>();
    controllers.add(controller);
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// An observations seam that answers each read only when the test says so.
class _HandFedObservations implements ObservationsRepository {
  final Map<String, Completer<List<Observation>>> reads = {};

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(String dayEntryId) =>
      (reads[dayEntryId] = Completer<List<Observation>>()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A tag registry whose one stream the test feeds by hand.
class _HandFedTagRegistry implements TagRegistryRepository {
  final List<String> watched = [];
  final StreamController<List<CustomTag>> controller =
      StreamController<List<CustomTag>>();

  @override
  Stream<List<CustomTag>> watchForProfile(String profileId) {
    watched.add(profileId);
    return controller.stream;
  }

  Future<void> close() => controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Probe extends StatefulWidget {
  const _Probe({
    required this.profileId,
    required this.entries,
    required this.observations,
    required this.today,
    required this.seen,
    this.dayTicks,
  });

  final String profileId;
  final DayEntriesRepository? entries;
  final ObservationsRepository? observations;
  final LocalDate Function() today;

  /// The caller's "the day may have changed" signal, if it has one.
  final Stream<Object?>? dayTicks;

  /// Every value the watch handed back, in order.
  final List<TodayLog?> seen;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with TodayLogWatchMixin<_Probe> {
  @override
  void initState() {
    super.initState();
    _watch();
  }

  void _watch() => watchTodayLog(
        entries: widget.entries,
        observations: widget.observations,
        profileId: widget.profileId,
        todayProvider: widget.today,
        onLog: (log) => setState(() => widget.seen.add(log)),
        dayTicks: widget.dayTicks,
      );

  @override
  void didUpdateWidget(covariant _Probe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) _watch();
  }

  @override
  void dispose() {
    disposeTodayLogWatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late _HandFedEntries entries;
  late _HandFedObservations observations;
  late List<TodayLog?> seen;

  /// The test's day-change signal. Broadcast, so it can be handed to a
  /// second subscription after a re-watch, and so it reports its listener
  /// gone the moment the watch lets go of it.
  late StreamController<Object?> dayTicks;

  setUp(() {
    entries = _HandFedEntries();
    observations = _HandFedObservations();
    seen = [];
    dayTicks = StreamController<Object?>.broadcast();
  });

  tearDown(() {
    unawaited(dayTicks.close());
  });

  Future<void> pump(
    WidgetTester tester, {
    String profileId = 'p1',
    bool withEntries = true,
    bool withObservations = true,
    bool withDayTicks = false,
    LocalDate Function()? today,
  }) =>
      tester.pumpWidget(
        _Probe(
          profileId: profileId,
          entries: withEntries ? entries : null,
          observations: withObservations ? observations : null,
          today: today ?? () => kToday,
          seen: seen,
          dayTicks: withDayTicks ? dayTicks.stream : null,
        ),
      );

  /// Tells every lifecycle observer the app has come back to the
  /// foreground, the way the engine does.
  void resumeApp(WidgetTester tester) => tester.binding
      .handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  testWidgets('says "not known yet" at once, and subscribes to the profile '
      'from the day before today with no end', (tester) async {
    await pump(tester);

    expect(seen, [null]);
    expect(entries.watches, hasLength(1));
    expect(entries.watches.single.profileId, 'p1');
    expect(entries.watches.single.from, kToday.addDays(-1));
    expect(entries.watches.single.to, isNull,
        reason: 'the first write after midnight has to arrive too');
  });

  testWidgets('with no entries seam it resets and subscribes to nothing',
      (tester) async {
    await pump(tester, withEntries: false);

    expect(seen, [null]);
    expect(entries.watches, isEmpty);
  });

  testWidgets('picks today\'s live entry out of the window, and reads its '
      'observations', (tester) async {
    await pump(tester);
    final today = entryOn(kToday);
    entries.latest.add([entryOn(kToday.addDays(-1), id: 'e0'), today]);
    await tester.pump();
    expect(seen, [null], reason: 'the observations read is still open');

    final spotting = spottingFor('e1');
    observations.reads['e1']!.complete([spotting]);
    await tester.pump();

    expect(seen, hasLength(2));
    final log = seen.last!;
    expect(log.entry, same(today));
    expect(log.observations, [spotting]);
    expect(observations.reads.keys, ['e1'],
        reason: 'only today\'s entry is read, never yesterday\'s');
  });

  testWidgets('a window with nothing for today is a log with no entry, and '
      'reads no observations', (tester) async {
    await pump(tester);
    entries.latest.add([entryOn(kToday.addDays(-1), id: 'e0')]);
    await tester.pump();

    expect(seen, hasLength(2));
    expect(seen.last!.entry, isNull);
    expect(seen.last!.observations, isEmpty);
    expect(observations.reads, isEmpty);
  });

  testWidgets('a tombstone for today is no entry', (tester) async {
    await pump(tester);
    entries.latest.add([entryOn(kToday, deletedAt: kNow)]);
    await tester.pump();

    expect(seen.last!.entry, isNull);
    expect(observations.reads, isEmpty);
  });

  testWidgets('with no observations seam the entry is handed back alone',
      (tester) async {
    await pump(tester, withObservations: false);
    final today = entryOn(kToday);
    entries.latest.add([today]);
    await tester.pump();

    expect(seen.last!.entry, same(today));
    expect(seen.last!.observations, isEmpty);
  });

  testWidgets('"today" is asked for again on every emission', (tester) async {
    var now = kToday;
    await pump(tester, withObservations: false, today: () => now);
    final first = entryOn(kToday);
    entries.latest.add([first]);
    await tester.pump();
    expect(seen.last!.entry, same(first));

    // Midnight passes. The same window now holds two days' entries, and
    // the one for the new day is today's.
    now = kToday.addDays(1);
    final tomorrow = entryOn(now, id: 'e2', tags: const ['headache']);
    entries.latest.add([first, tomorrow]);
    await tester.pump();
    expect(seen.last!.entry, same(tomorrow));

    // And with nothing for the new day, yesterday's is not offered.
    entries.latest.add([first]);
    await tester.pump();
    expect(seen.last!.entry, isNull);
  });

  testWidgets('an answer overtaken by a newer emission is dropped',
      (tester) async {
    await pump(tester);
    final first = entryOn(kToday, id: 'first');
    final second = entryOn(kToday, id: 'second', tags: const ['headache']);
    entries.latest.add([first]);
    await tester.pump();
    entries.latest.add([second]);
    await tester.pump();

    // The newer read lands first; the older one must not then replace it.
    observations.reads['second']!.complete(const []);
    await tester.pump();
    expect(seen.last!.entry, same(second));
    final settled = seen.length;

    observations.reads['first']!.complete([spottingFor('first')]);
    await tester.pump();
    expect(seen, hasLength(settled));
    expect(seen.last!.entry, same(second));
  });

  testWidgets('a re-watch cancels the old subscription, resets at once, and '
      'drops the old profile\'s open read', (tester) async {
    await pump(tester);
    entries.latest.add([entryOn(kToday)]);
    await tester.pump();
    expect(entries.isListenedTo(0), isTrue);

    await pump(tester, profileId: 'p2');
    expect(entries.isListenedTo(0), isFalse);
    expect(entries.isListenedTo(1), isTrue);
    expect(entries.watches.last.profileId, 'p2');
    expect(seen, [null, null]);

    // The first profile's read answers only now: it must not surface.
    observations.reads['e1']!.complete([spottingFor('e1')]);
    await tester.pump();
    expect(seen, [null, null]);
  });

  testWidgets('dispose cancels the subscription, and an answer that arrives '
      'afterwards is dropped', (tester) async {
    await pump(tester);
    entries.latest.add([entryOn(kToday)]);
    await tester.pump();
    expect(entries.isListenedTo(0), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(entries.isListenedTo(0), isFalse);

    observations.reads['e1']!.complete(const []);
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'no setState after dispose');
    expect(seen, [null]);
  });

  testWidgets('a stream error is recorded and dropped; the watch keeps going',
      (tester) async {
    await pump(tester, withObservations: false);
    entries.latest.addError(StateError('simulated'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(seen, [null]);

    final today = entryOn(kToday);
    entries.latest.add([today]);
    await tester.pump();
    expect(seen.last!.entry, same(today));
  });

  testWidgets('a failed observations read costs the observations, not the '
      'entry', (tester) async {
    await pump(tester);
    final today = entryOn(kToday);
    entries.latest.add([today]);
    await tester.pump();

    observations.reads['e1']!.completeError(StateError('simulated'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(seen.last!.entry, same(today));
    expect(seen.last!.observations, isEmpty);
  });

  group('a new day with nothing written', () {
    testWidgets('a day tick on the same day reads nothing again',
        (tester) async {
      await pump(tester, withObservations: false, withDayTicks: true);
      entries.latest.add([entryOn(kToday)]);
      await tester.pump();
      expect(seen, hasLength(2));

      dayTicks.add(null);
      await tester.pump();
      expect(seen, hasLength(2));
    });

    testWidgets('a day tick on a new day answers from the window in hand: '
        'yesterday\'s entry is no longer today\'s', (tester) async {
      var now = kToday;
      await pump(
        tester,
        withObservations: false,
        withDayTicks: true,
        today: () => now,
      );
      final first = entryOn(kToday);
      entries.latest.add([first]);
      await tester.pump();
      expect(seen.last!.entry, same(first));

      now = kToday.addDays(1);
      dayTicks.add(null);
      await tester.pump();
      expect(seen, hasLength(3));
      expect(seen.last!.entry, isNull);
      expect(seen.last!.hasContent, isFalse);
      expect(entries.watches, hasLength(1),
          reason: 'answered from the window in hand, not a new subscription');

      // The same day ticking again is not a reason to read again.
      dayTicks.add(null);
      await tester.pump();
      expect(seen, hasLength(3));
    });

    testWidgets('a day that moves back picks that day\'s entry out of the '
        'window, and reads its observations', (tester) async {
      var now = kToday;
      await pump(tester, withDayTicks: true, today: () => now);
      final yesterday = entryOn(kToday.addDays(-1), id: 'e0');
      entries.latest.add([yesterday, entryOn(kToday)]);
      await tester.pump();
      observations.reads['e1']!.complete(const []);
      await tester.pump();
      expect(seen.last!.entry!.id, 'e1');

      // A flight west: the clock is on the day before again.
      now = kToday.addDays(-1);
      dayTicks.add(null);
      await tester.pump();
      final spotting = spottingFor('e0');
      observations.reads['e0']!.complete([spotting]);
      await tester.pump();
      expect(seen.last!.entry, same(yesterday));
      expect(seen.last!.observations, [spotting]);
    });

    testWidgets('a day tick before anything has been read does nothing',
        (tester) async {
      var now = kToday;
      await pump(tester, withDayTicks: true, today: () => now);
      now = kToday.addDays(1);
      dayTicks.add(null);
      await tester.pump();

      expect(seen, [null]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('returning to the foreground on a new day reads again, with '
        'no day-tick stream at all', (tester) async {
      var now = kToday;
      await pump(tester, withObservations: false, today: () => now);
      final first = entryOn(kToday);
      entries.latest.add([first]);
      await tester.pump();
      expect(seen.last!.entry, same(first));

      // Back in the foreground on the same day: nothing to do.
      resumeApp(tester);
      await tester.pump();
      expect(seen, hasLength(2));

      // Opened again the next morning.
      now = kToday.addDays(1);
      resumeApp(tester);
      await tester.pump();
      expect(seen, hasLength(3));
      expect(seen.last!.entry, isNull);
    });

    testWidgets('going to the background is not a reason to read',
        (tester) async {
      var now = kToday;
      await pump(tester, withObservations: false, today: () => now);
      entries.latest.add([entryOn(kToday)]);
      await tester.pump();

      now = kToday.addDays(1);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(seen, hasLength(2));

      resumeApp(tester);
      await tester.pump();
      expect(seen, hasLength(3));
    });

    testWidgets('an error on the day-tick stream is ignored, and later '
        'ticks still count', (tester) async {
      var now = kToday;
      await pump(
        tester,
        withObservations: false,
        withDayTicks: true,
        today: () => now,
      );
      entries.latest.add([entryOn(kToday)]);
      await tester.pump();

      dayTicks.addError(StateError('simulated'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(seen, hasLength(2));

      now = kToday.addDays(1);
      dayTicks.add(null);
      await tester.pump();
      expect(seen, hasLength(3));
      expect(seen.last!.entry, isNull);
    });

    testWidgets('a re-watch keeps listening for the day, and dispose lets '
        'go of it', (tester) async {
      var now = kToday;
      await pump(
        tester,
        withObservations: false,
        withDayTicks: true,
        today: () => now,
      );
      expect(dayTicks.hasListener, isTrue);

      await pump(
        tester,
        profileId: 'p2',
        withObservations: false,
        withDayTicks: true,
        today: () => now,
      );
      expect(dayTicks.hasListener, isTrue);
      entries.latest.add([entryOn(kToday)]);
      await tester.pump();
      final settled = seen.length;

      await tester.pumpWidget(const SizedBox.shrink());
      expect(dayTicks.hasListener, isFalse);

      // Nothing is read for a widget that has gone, by either route.
      now = kToday.addDays(1);
      dayTicks.add(null);
      resumeApp(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(seen, hasLength(settled));
    });
  });

  test('the custom-tag names stream drops an error and keeps going', () async {
    final registry = _HandFedTagRegistry();
    final received = <List<CustomTag>>[];
    // No onError here: an error this stream forwarded would fail the test
    // as an uncaught one.
    final subscription =
        watchCustomTagsSafely(registry, 'p1').listen(received.add);
    expect(registry.watched, ['p1']);

    registry.controller.addError(StateError('simulated'));
    await pumpEventQueue();
    expect(received, isEmpty);

    final tags = [
      CustomTag(
        id: 't1',
        profileId: 'p1',
        code: 'back_cracking',
        displayName: 'Back cracking',
        category: kCustomTagCategory,
        createdAt: kNow,
        updatedAt: kNow,
      ),
    ];
    registry.controller.add(tags);
    await pumpEventQueue();
    expect(received, [tags]);

    await subscription.cancel();
    await registry.close();
  });
}
