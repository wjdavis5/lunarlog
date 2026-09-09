import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/ui/logging/widgets/caregiver_attribution_badge.dart';

void main() {
  final guardianDad = ProfileGuardian(
    id: 'g-1',
    profileId: 'p-1',
    userId: 'user-dad',
    role: GuardianRole.coParent,
    status: GuardianStatus.accepted,
    displayName: 'Dad',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  final guardianMom = ProfileGuardian(
    id: 'g-2',
    profileId: 'p-1',
    userId: 'user-mom',
    role: GuardianRole.primaryGuardian,
    status: GuardianStatus.accepted,
    displayName: 'Mom',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  testWidgets('renders nothing when attribution ids are null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaregiverAttributionBadge(
            loggedByUserId: null,
            lastModifiedByUserId: null,
          ),
        ),
      ),
    );

    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders "Logged by you" when loggedByUserId equals currentUserId', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaregiverAttributionBadge(
            loggedByUserId: 'user-me',
            lastModifiedByUserId: 'user-me',
            currentUserId: 'user-me',
          ),
        ),
      ),
    );

    expect(find.text('Logged by you'), findsOneWidget);
  });

  testWidgets('renders guardian display name when available', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaregiverAttributionBadge(
            loggedByUserId: 'user-dad',
            currentUserId: 'user-mom',
            guardians: [guardianDad, guardianMom],
          ),
        ),
      ),
    );

    expect(find.text('Logged by Dad'), findsOneWidget);
  });

  testWidgets('#138: the badge is one semantic node announcing who logged '
      'the entry, with the decorative icon excluded and no ellipsis to '
      'truncate the name at large text scales', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(200, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: CaregiverAttributionBadge(
              loggedByUserId: 'user-dad',
              currentUserId: 'user-mom',
              guardians: [guardianDad, guardianMom],
            ),
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(CaregiverAttributionBadge));
    expect(node.label, 'Logged by Dad',
        reason: 'the badge announces its attribution as a single focus stop, '
            'not decorative icon plus stray text');
    expect(
      node.childrenCount,
      0,
      reason: 'the icon and the text merge into the one container node — '
          'nothing of the badge is a second focus stop',
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.overflow, isNot(TextOverflow.ellipsis),
        reason: '#138 AC4: the name wraps at 200% instead of truncating');
    expect(tester.takeException(), isNull,
        reason: 'no layout overflow at 200% text scale');
    handle.dispose();
  });

  testWidgets('renders both logged by and modified by when different users modified', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CaregiverAttributionBadge(
            loggedByUserId: 'user-dad',
            lastModifiedByUserId: 'user-mom',
            currentUserId: 'user-mom',
            guardians: [guardianDad, guardianMom],
          ),
        ),
      ),
    );

    expect(find.text('Logged by Dad • Modified by you'), findsOneWidget);
  });

  testWidgets('renders "Imported from Clue" for a clue_import row, never a guardian name',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaregiverAttributionBadge(
            loggedByUserId: 'user-dad',
            lastModifiedByUserId: 'user-dad',
            currentUserId: 'user-mom',
            source: 'clue_import',
          ),
        ),
      ),
    );

    expect(find.text('Imported from Clue'), findsOneWidget);
    expect(find.textContaining('Logged by'), findsNothing);
  });

  testWidgets('renders even with no attribution ids when source is non-manual', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaregiverAttributionBadge(
            loggedByUserId: null,
            lastModifiedByUserId: null,
            source: 'healthkit',
          ),
        ),
      ),
    );

    expect(find.text('Imported from Health'), findsOneWidget);
  });

  testWidgets('falls back to "Imported" for an unrecognised source value', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaregiverAttributionBadge(
            loggedByUserId: null,
            source: 'some_future_source',
          ),
        ),
      ),
    );

    expect(find.text('Imported'), findsOneWidget);
  });

  // Issue #159 review finding: `_sourceLabel`'s remaining arms (the
  // `healthkit || apple_health` shared arm's other member, plus
  // health_connect/file_import/wearable) were never exercised — only
  // clue_import, healthkit, and the fallback default were. Table-driven
  // over every arm not already covered above, mirroring
  // `day_entry_test.dart`'s `DayEntrySource` coverage.
  for (final MapEntry(key: source, value: label) in const {
    'apple_health': 'Imported from Health',
    'health_connect': 'Imported from Health Connect',
    'file_import': 'Imported from file',
    'wearable': 'Imported from wearable',
  }.entries) {
    testWidgets('renders "$label" for a $source row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CaregiverAttributionBadge(
              loggedByUserId: null,
              source: source,
            ),
          ),
        ),
      );

      expect(find.text(label), findsOneWidget);
    });
  }
}
