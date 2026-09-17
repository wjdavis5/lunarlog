/// Widget tests for the day sheet's merge notice (Issue #130): the notice
/// renders for BOTH guardians (the winner sees it too), names the field
/// and whose value was kept, offers text recovery only to the losing
/// author, dismisses per device, and renders nothing without events (a
/// tags-only merge or a same-id convergence never produces one).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/ui/logging/widgets/merge_notice_section.dart';


DayEntryMergeEvent event({
  String id = '01JREMOTE00000000000000000A',
  DayEntryMergeEventField field = DayEntryMergeEventField.note,
  String losingValueText = 'she stayed home from school',
  String? losingAuthorUserId = 'user-loser',
  String? winningAuthorUserId = 'user-winner',
}) =>
    DayEntryMergeEvent(
      id: id,
      profileId: 'p1',
      localDateIso: '2026-01-15',
      winningRowId: '01JREMOTE00000000000000000W',
      losingRowId: '01JREMOTE00000000000000000L',
      field: field,
      losingValueText: losingValueText,
      losingAuthorUserId: losingAuthorUserId,
      winningAuthorUserId: winningAuthorUserId,
      createdAt: DateTime.utc(2026, 1, 16),
      updatedAt: DateTime.utc(2026, 1, 16),
    );

/// The [event] fixture with only [DayEntryMergeEvent.createdAt] changed —
/// one differing field at a time keeps the equality walk exhaustive.
DayEntryMergeEvent _eventWithCreatedAt(DateTime createdAt) {
  final base = event();
  return DayEntryMergeEvent(
    id: base.id,
    profileId: base.profileId,
    localDateIso: base.localDateIso,
    winningRowId: base.winningRowId,
    losingRowId: base.losingRowId,
    field: base.field,
    losingValueText: base.losingValueText,
    losingAuthorUserId: base.losingAuthorUserId,
    winningAuthorUserId: base.winningAuthorUserId,
    createdAt: createdAt,
    updatedAt: base.updatedAt,
  );
}

ProfileGuardian guardian(String userId, String name) => ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p1',
      userId: userId,
      role: GuardianRole.coParent,
      displayName: name,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> pumpSection(
  WidgetTester tester, {
  required List<DayEntryMergeEvent> events,
  String? currentUserId,
  void Function(DayEntryMergeEvent)? onDismiss,
  void Function(DayEntryMergeEvent)? onRestoreNote,
  void Function(DayEntryMergeEvent)? onRestoreFlow,
}) async {
  dismissed(DayEntryMergeEvent e) => onDismiss?.call(e);
  restoreNote(DayEntryMergeEvent e) => onRestoreNote?.call(e);
  restoreFlow(DayEntryMergeEvent e) => onRestoreFlow?.call(e);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DayEntryMergeNoticeSection(
            events: events,
            currentUserId: currentUserId,
            guardians: [
              guardian('user-winner', 'Dad'),
              guardian('user-loser', 'Mom'),
            ],
            onDismiss: dismissed,
            onRestoreNote: restoreNote,
            onRestoreFlow: restoreFlow,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('DayEntryMergeEventField round-trips the wire strings', () {
    expect(DayEntryMergeEventField.flow.toDb(), 'flow');
    expect(DayEntryMergeEventField.note.toDb(), 'note');
    expect(DayEntryMergeEventField.fromDb('flow'),
        DayEntryMergeEventField.flow);
    expect(DayEntryMergeEventField.fromDb('note'),
        DayEntryMergeEventField.note);
    // A broken writer's value degrades to note, never throws.
    expect(DayEntryMergeEventField.fromDb('tags'),
        DayEntryMergeEventField.note);
  });

  test('DayEntryMergeEvent has full value semantics over every field', () {
    final a = event();
    expect(a, event());
    expect(a.hashCode, event().hashCode);
    expect(a, isNot(event(id: '01JREMOTE00000000000000000C')));
    expect(a, isNot(event(field: DayEntryMergeEventField.flow)));
    expect(a, isNot(event(losingValueText: 'different text')));
    expect(a, isNot(event(losingAuthorUserId: 'someone-else')));
    expect(a, isNot(event(winningAuthorUserId: 'someone-else')));
    expect(a, isNot(_eventWithCreatedAt(DateTime.utc(2026, 2, 1))));
    expect(a, isNot('not an event'));
  });

  testWidgets('no events renders nothing (tags-only/same-id silence)',
      (tester) async {
    await pumpSection(tester, events: const [], currentUserId: 'user-loser');
    expect(find.byKey(const ValueKey('merge-notice-section')), findsNothing);
  });

  testWidgets('the losing author sees the notice, the discarded text, and '
      'a restore affordance', (tester) async {
    var restored = false;
    await pumpSection(
      tester,
      events: [event()],
      currentUserId: 'user-loser',
      onRestoreNote: (_) => restored = true,
    );
    // One sentence naming the field and whose value was kept (AC).
    expect(find.textContaining("your note was kept"), findsNothing);
    expect(find.textContaining("Dad's note was kept"), findsOneWidget);
    expect(find.textContaining('your note was discarded'), findsOneWidget);
    // The recoverable text itself (the keyed Text IS the retained text).
    expect(
        find.byKey(const ValueKey('merge-notice-lost-text')),
        findsOneWidget);
    expect(find.text('she stayed home from school'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('merge-notice-restore')));
    await tester.pump();
    expect(restored, isTrue);
  });

  testWidgets('the winning guardian sees the notice too, but no recovery '
      'affordance and no discarded text', (tester) async {
    await pumpSection(tester, events: [event()], currentUserId: 'user-winner');
    expect(find.textContaining('your note was kept'), findsOneWidget);
    expect(find.textContaining("Mom's note was discarded"), findsOneWidget);
    expect(find.byKey(const ValueKey('merge-notice-lost-text')), findsNothing);
    expect(find.byKey(const ValueKey('merge-notice-restore')), findsNothing);
  });

  testWidgets('a flow discard names the flow field and restores through the '
      'flow callback', (tester) async {
    var restoredFlow = false;
    await pumpSection(
      tester,
      events: [
        event(
          id: '01JREMOTE00000000000000000B',
          field: DayEntryMergeEventField.flow,
          losingValueText: 'heavy',
        ),
      ],
      currentUserId: 'user-loser',
      onRestoreFlow: (_) => restoredFlow = true,
    );
    expect(find.textContaining('flow level was kept'), findsOneWidget);
    expect(find.byKey(const ValueKey('merge-notice-lost-text')), findsNothing,
        reason: 'only a note discard renders its retained text inline');
    await tester.tap(find.byKey(const ValueKey('merge-notice-restore')));
    await tester.pump();
    expect(restoredFlow, isTrue);
  });

  testWidgets('dismissing fires the callback and drops the row',
      (tester) async {
    final dismissedIds = <String>[];
    await pumpSection(
      tester,
      events: [event()],
      currentUserId: 'user-winner',
      onDismiss: (e) => dismissedIds.add(e.id),
    );
    await tester.tap(find.byKey(const ValueKey('merge-notice-dismiss')));
    await tester.pump();
    expect(dismissedIds, ['01JREMOTE00000000000000000A']);
  });

  testWidgets('an unattributed author renders the generic phrase instead of '
      'a name', (tester) async {
    await pumpSection(
      tester,
      events: [event(losingAuthorUserId: null, winningAuthorUserId: null)],
      currentUserId: 'user-winner',
    );
    expect(find.textContaining('another guardian'), findsWidgets);
  });
}
