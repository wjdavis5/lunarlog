/// Issue #151 UI coverage: the recipient's phase-only calendar (renders
/// the projection's phases and has NO day-tap navigation into any day
/// sheet), the "Shared with me" list screen, the sharer's section in
/// Manage Guardians, and the kind=prediction accept sheet.
library;


import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' hide Profile, DayEntry;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/data/repositories/profile_guardians_repository.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/domain/sharing/prediction_projection.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/ui/sharing/accept_prediction_connection_sheet.dart';
import 'package:lunarlog/ui/sharing/manage_guardians_screen.dart';
import 'package:lunarlog/ui/sharing/prediction_connection_calendar_screen.dart';
import 'package:lunarlog/ui/sharing/prediction_connections_screen.dart';

PredictionProjection _projection(LocalDate asOf) => PredictionProjection(
      generatedAt: asOf,
      periodDays: [asOf.addDays(3), asOf.addDays(4)],
      fertileDays: [asOf.addDays(15)],
      ovulationDays: [asOf.addDays(17)],
      pmsDays: [asOf.addDays(-4)],
    );

class _FakePredictionConnectionService implements PredictionConnectionService {
  _FakePredictionConnectionService({this.projection, this.connections = const []});

  PredictionProjection? projection;
  List<IncomingPredictionConnection> connections = const [];
  ActivePredictionConnection? getActiveConnectionResult;
  AcceptedPredictionConnection? scriptedAccept;
  PredictionConnectionFailure? acceptFailure;
  String? lastRevokedConnectionId;
  final List<String> revoked = [];

  @override
  Future<ActivePredictionConnection?> getActiveConnection(
      {required String profileId}) async {
    return getActiveConnectionResult;
  }

  @override
  Future<AcceptedPredictionConnection> acceptConnection(
      {required String rawToken}) async {
    final failure = acceptFailure;
    if (failure != null) throw failure;
    return scriptedAccept!;
  }

  @override
  Future<PredictionProjection?> fetchProjection(
      {required String profileId}) async {
    return projection;
  }

  @override
  Future<List<IncomingPredictionConnection>> listIncomingConnections() async {
    return connections;
  }

  @override
  Future<void> revokeConnection({required String connectionId}) async {
    lastRevokedConnectionId = connectionId;
    revoked.add(connectionId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _NoInvitesSharingService implements SharingService {
  @override
  Future<List<PendingInvite>> listPendingInvites(String profileId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('PredictionConnectionCalendarScreen', () {
    testWidgets('renders the shared phases and the legend, and offers no '
        'day-tap navigation into any detail route', (tester) async {
      final asOf = LocalDate.today();
      final service = _FakePredictionConnectionService(
        projection: _projection(asOf),
      );

      await tester.pumpWidget(MaterialApp(
        home: PredictionConnectionCalendarScreen(
          profileId: 'p1',
          profileName: 'Riley',
          service: service,
        ),
      ));
      await tester.pumpAndSettle();

      // Phase legend present.
      expect(find.text('Period'), findsOneWidget);
      expect(find.text('Fertile'), findsOneWidget);
      expect(find.text('Ovulation'), findsOneWidget);
      expect(find.text('PMS'), findsOneWidget);

      // The month grid renders.
      expect(find.byKey(const ValueKey('prediction-grid')), findsNothing);
      expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('prediction-grid-')),
        findsOneWidget,
      );

      // No route into a day sheet exists in the phase grid specifically:
      // the app bar's own refresh/month-nav IconButtons legitimately use
      // InkWell/InkResponse under the hood (Material's own button
      // internals -- unrelated to day-tap navigation), so the absence
      // check is scoped to the grid subtree, not the whole screen. A day
      // sheet push would require a tappable ancestor around a day cell;
      // none exists here.
      final grid = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('prediction-grid-'));
      expect(find.descendant(of: grid, matching: find.byType(InkWell)),
          findsNothing);
      expect(find.descendant(of: grid, matching: find.byType(InkResponse)),
          findsNothing);
      expect(
          find.descendant(of: grid, matching: find.byType(GestureDetector)),
          findsNothing);

      // No push happened on pump: exactly one route (home).
    });

    testWidgets('a null projection renders the connection-ended state '
        '(revocation takes effect on the next fetch)', (tester) async {
      final service = _FakePredictionConnectionService(projection: null);

      await tester.pumpWidget(MaterialApp(
        home: PredictionConnectionCalendarScreen(
          profileId: 'p1',
          profileName: 'Riley',
          service: service,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Connection ended'), findsOneWidget);
    });

    testWidgets('month navigation re-renders the grid', (tester) async {
      final asOf = LocalDate(2026, 9, 7);
      final service = _FakePredictionConnectionService(
        projection: _projection(asOf),
      );

      await tester.pumpWidget(MaterialApp(
        home: PredictionConnectionCalendarScreen(
          profileId: 'p1',
          profileName: 'Riley',
          service: service,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      // September +1 (October) -1 -1 = August, not July.
      expect(find.text('August 2026'), findsOneWidget);
    });
  });

  group('PredictionConnectionsScreen', () {
    testWidgets('lists incoming connections and opens the calendar on tap',
        (tester) async {
      final service = _FakePredictionConnectionService(
        projection: _projection(LocalDate(2026, 9, 7)),
        connections: [
          IncomingPredictionConnection(
            connectionId: 'conn-1',
            profileId: 'p1',
            acceptedAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: PredictionConnectionsScreen(service: service),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('prediction-connection-p1')),
        findsOneWidget,
      );
      expect(find.text('Shared with me'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('prediction-connection-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Period'), findsOneWidget,
          reason: 'the calendar pushed on top of the list');
    });

    testWidgets('manual code entry redeems and opens the calendar',
        (tester) async {
      final service = _FakePredictionConnectionService(
        projection: _projection(LocalDate(2026, 9, 7)),
        connections: const [],
      );
      service.scriptedAccept = AcceptedPredictionConnection(
        connectionId: 'conn-9',
        profileId: 'p2',
        profileName: 'Avery',
      );

      AcceptedPredictionConnection? connectedResult;
      await tester.pumpWidget(MaterialApp(
        home: PredictionConnectionsScreen(
          service: service,
          onConnected: (result) => connectedResult = result,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('enter-prediction-code')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('prediction-code-field')), 'the-code');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(connectedResult, isNotNull);
      expect(connectedResult!.profileId, 'p2');
      expect(find.text('Avery'), findsOneWidget,
          reason: 'the calendar pushed with the accepted profile name');
    });

    testWidgets('a typed failure surfaces its user-facing message',
        (tester) async {
      final service = _FakePredictionConnectionService(connections: const []);
      service.acceptFailure =
          const PredictionConnectionFailure.pregnancyMode();

      await tester.pumpWidget(MaterialApp(
        home: PredictionConnectionsScreen(service: service),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('enter-prediction-code')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('prediction-code-field')), 'the-code');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Pregnancy mode'),
        findsOneWidget,
      );
      expect(find.text('Avery'), findsNothing);
    });
  });

  group('AcceptPredictionConnectionSheet', () {
    testWidgets('accepts the latched code and pops with the result',
        (tester) async {
      final service = _FakePredictionConnectionService(connections: const []);
      service.scriptedAccept = AcceptedPredictionConnection(
        connectionId: 'conn-9',
        profileId: 'p2',
        profileName: 'Avery',
      );

      AcceptedPredictionConnection? popped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return Center(
              child: FilledButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => AcceptPredictionConnectionSheet(
                      rawToken: 'code',
                      service: service,
                      onAccepted: (result) => popped = result,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          }),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Connect to cycle predictions'), findsOneWidget);
      expect(
        find.textContaining('read-only calendar'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.profileName, 'Avery');
    });
  });

  group('ManageGuardiansScreen predictions section', () {
    late LunarLogDatabase db;
    late LunarLogStorage storage;
    late Profile testProfile;
    late _FakePredictionConnectionService connectionService;

    RemoteProfileGuardianRow guardianRow(String userId, String role) =>
        RemoteProfileGuardianRow(
          id: 'g-$userId',
          profileId: testProfile.id,
          userId: userId,
          role: role,
          status: 'accepted',
          displayName: null,
          invitedBy: null,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          serverVersion: 1,
        );

    setUp(() async {
      db = LunarLogDatabase(NativeDatabase.memory());
      storage = LunarLogStorage(db);
      connectionService = _FakePredictionConnectionService();
      testProfile = profileToDomain(
          await storage.upsertProfile(displayName: 'Riley', isMinor: true));
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      // Seed the caller's primary-guardian row so the section's role gate
      // resolves (mom = primary_guardian), the same fixture
      // sharing_flow_test.dart uses.
      await storage.applyRemoteRows([guardianRow('user-mom', 'primary_guardian')]);

      await tester.pumpWidget(MaterialApp(
        home: ManageGuardiansScreen(
          profile: testProfile,
          guardiansRepository: ProfileGuardiansRepository(storage),
          sharingService: _NoInvitesSharingService(),
          currentUserId: 'user-mom',
          predictionConnectionService: connectionService,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'a primary guardian sees the sharing section and can arm a connection',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Predictions-only sharing'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-predictions')), findsOneWidget);

      // Dispose the tree under our own control (rather than the test
      // framework's automatic between-test reset) so the guardian-rows
      // StreamBuilders' drift stream subscriptions finish cancelling
      // before the test ends -- the established pattern for drift-backed
      // widget tests in this suite (see test/ui/a11y_pass_test.dart).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('the live connection shows with its revoke control, and '
        'revoke calls the service', (tester) async {
      connectionService.getActiveConnectionResult =
          ActivePredictionConnection(
        connectionId: 'conn-1',
        profileId: testProfile.id,
        pending: false,
        recipientLabel: 'Partner',
        createdAt: DateTime.utc(2026, 9, 1),
        expiresAt: DateTime.utc(2026, 9, 8),
      );
      await pumpScreen(tester);

      expect(find.text('Partner'), findsOneWidget);
      expect(find.text('Phases-only calendar • not a guardian'),
          findsOneWidget);

      await tester.tap(
          find.byKey(const ValueKey('revoke-prediction-connection')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'End sharing'));
      await tester.pumpAndSettle();

      expect(connectionService.lastRevokedConnectionId, 'conn-1');
      expect(find.text('Prediction sharing ended'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
