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
