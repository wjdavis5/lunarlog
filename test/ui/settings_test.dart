import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/feedback/feedback_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/feedback/feedback_screen.dart' show kSupportEmailAddress;
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_feedback_service.dart';

class FakeSettingsStore implements SettingsStore {
  final Map<String, String> _values = {};
  final _controllers = <String, StreamController<String?>>{};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async {
    _values[key] = value;
    _controllers[key]?.add(value);
  }

  @override
  Stream<String?> watch(String key) {
    final c = _controllers.putIfAbsent(
      key,
      () => StreamController<String?>.broadcast(),
    );
    return Stream.value(_values[key]).concatWith([c.stream]);
  }
}

extension on Stream<String?> {
  Stream<String?> concatWith(List<Stream<String?>> others) async* {
    yield* this;
    for (final s in others) {
      yield* s;
    }
  }
}

void main() {
  testWidgets('SettingsScreen displays Privacy policy tile and opens dialog',
      (tester) async {
    final settingsStore = FakeSettingsStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Provider<SettingsStore>.value(
          value: settingsStore,
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify relock toggle is present
    expect(find.byKey(const ValueKey('relock-toggle')), findsOneWidget);

    // Verify privacy policy tile is present
    final privacyTile = find.byKey(const ValueKey('privacy-policy-tile'));
    expect(privacyTile, findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Local-first, encrypted, zero tracking'), findsOneWidget);

    // Tap privacy policy tile
    await tester.tap(privacyTile);
    await tester.pumpAndSettle();

    // Verify dialog opened
    expect(find.text('LunarLog Privacy Policy'), findsOneWidget);
    expect(find.textContaining('Local & Encrypted'), findsOneWidget);
    expect(find.textContaining('Zero Ads & Tracking'), findsOneWidget);

    // Tap Close button
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Verify dialog closed
    expect(find.text('LunarLog Privacy Policy'), findsNothing);
  });

  /// A signed-in [AuthController] so `hasFeedback` (R23) can turn true in a
  /// test — feedback needs both a `FeedbackService` and a live session.
  AuthController signedInAuth() {
    final service = FakeAuthService()
      ..emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1', email: 'a@b.c'));
    addTearDown(service.dispose);
    final controller = AuthController(authService: service);
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('shows send-feedback-tile when signed in with a FeedbackService, and hides it '
      'when no FeedbackService is provided', (tester) async {
    final settingsStore = FakeSettingsStore();

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<SettingsStore>.value(value: settingsStore),
            Provider<FeedbackService>.value(value: FakeFeedbackService()),
            ChangeNotifierProvider<AuthController>.value(value: signedInAuth()),
          ],
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-feedback-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-support-tile')), findsNothing);
  });

  testWidgets('shows contact-support-tile when no FeedbackService is provided, and the dialog '
      'contains the support address', (tester) async {
    final settingsStore = FakeSettingsStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Provider<SettingsStore>.value(
          value: settingsStore,
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-feedback-tile')), findsNothing);
    final supportTile = find.byKey(const ValueKey('contact-support-tile'));
    expect(supportTile, findsOneWidget);

    await tester.tap(supportTile);
    await tester.pumpAndSettle();

    expect(find.text(kSupportEmailAddress), findsOneWidget);
  });

  testWidgets('R23: a signed-out session with a configured FeedbackService still shows '
      'contact-support-tile, not the form — a signed-out tap must not hit the '
      'permission error a form submission would throw', (tester) async {
    final settingsStore = FakeSettingsStore();
    final auth = FakeAuthService(); // defaults to signedOut
    addTearDown(auth.dispose);
    final controller = AuthController(authService: auth);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<SettingsStore>.value(value: settingsStore),
            Provider<FeedbackService>.value(value: FakeFeedbackService()),
            ChangeNotifierProvider<AuthController>.value(value: controller),
          ],
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('send-feedback-tile')), findsNothing);
    final supportTile = find.byKey(const ValueKey('contact-support-tile'));
    expect(supportTile, findsOneWidget);

    await tester.tap(supportTile);
    await tester.pumpAndSettle();

    expect(find.text(kSupportEmailAddress), findsOneWidget);
  });

  FeedbackTicket repliedTicket(DateTime updatedAt) => FeedbackTicket(
        id: 't1',
        category: FeedbackCategory.bug,
        message: 'crashed',
        replyEmail: 'a@example.com',
        status: FeedbackTicketStatus.replied,
        attachmentPaths: const [],
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );

  testWidgets('support-history-tile shows the unread badge when a reply is newer than the '
      'stored feedbackLastSeenAt', (tester) async {
    final settingsStore = FakeSettingsStore()
      .._values[SettingsKeys.feedbackLastSeenAt] = DateTime.utc(2026, 1, 1).toIso8601String();
    final service = FakeFeedbackService()..ticketsToReturn = [repliedTicket(DateTime.utc(2026, 9, 5))];

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<SettingsStore>.value(value: settingsStore),
            Provider<FeedbackService>.value(value: service),
            ChangeNotifierProvider<AuthController>.value(value: signedInAuth()),
          ],
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-history-unread-badge')), findsOneWidget);
  });

  testWidgets('support-history-tile has no unread badge when feedbackLastSeenAt is already '
      'as new as the newest reply', (tester) async {
    final newest = DateTime.utc(2026, 9, 5);
    final settingsStore = FakeSettingsStore().._values[SettingsKeys.feedbackLastSeenAt] = newest.toIso8601String();
    final service = FakeFeedbackService()..ticketsToReturn = [repliedTicket(newest)];

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<SettingsStore>.value(value: settingsStore),
            Provider<FeedbackService>.value(value: service),
            ChangeNotifierProvider<AuthController>.value(value: signedInAuth()),
          ],
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-history-unread-badge')), findsNothing);
  });

  testWidgets('support-history-tile swallows a listTickets failure and shows no badge', (tester) async {
    final settingsStore = FakeSettingsStore();
    final service = FakeFeedbackService()..failWithOnListTickets = const FeedbackFailure.network();

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<SettingsStore>.value(value: settingsStore),
            Provider<FeedbackService>.value(value: service),
            ChangeNotifierProvider<AuthController>.value(value: signedInAuth()),
          ],
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-history-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-history-unread-badge')), findsNothing);
  });
}
