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
}
