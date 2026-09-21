/// U8 web guardrail tests (KTD9), updated by epic #831 (Option A): the web
/// build is a first-class client when `LUNARLOG_WEB_SYNC=true`, so the
/// banner and the one-time first-run acknowledgement are selected by that
/// flag through the injectable `webSyncEnabled` seam.
///
/// Also Issue #17 R11 (KTD9's own rule extended): "Delete account" never
/// ships on web, regardless of `LUNARLOG_WEB_SYNC` ("Export my data" moved
/// to `YourDataSection` under Issue #222 - its own web guard is covered in
/// `test/ui/your_data_section_test.dart`, not here). `kIsWeb` cannot be
/// forced true inside a `flutter test` VM run, so this uses
/// [AccountSection.showExportAndDelete] as the injectable proxy for "is
/// web", the same technique `showAddApple`/`showAddGoogle` already use for
/// "is iOS" (`test/ui/account_test.dart`).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/web/dev_banner.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

const String kDevBannerCopy = 'Development build — not for real data.';
const String kSyncedBannerCopy = 'Browser build — this browser stores a copy '
    "of the signed-in profiles' data unencrypted, plus your sign-in. "
    'Signing out clears it.';

/// Mounts [child] under a `MaterialApp` that carries the app's real
/// localization delegates, since the banner reads its copy through
/// `AppLocalizations`.
Widget _localizedApp(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the app wires the wipe to the device reset callback (KTD16)',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    var resets = 0;
    await tester.pumpWidget(LunarLogApp.withCollaborators(
      db: db,
      showWebBanner: true,
      resetDevice: () async {
        resets++;
        await db.wipeAllData();
      },
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WebDevBanner.wipeButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('web-wipe-confirm')));
    await tester.pumpAndSettle();
    expect(resets, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  });

  testWidgets('banner copy: sync off keeps the dev warning and offers no '
      'dismiss; sync on is an honest browser notice that never says "not for '
      'real data"', (tester) async {
    await tester.pumpWidget(_localizedApp(
      WebGuardrails(
        showBanner: true,
        onWipe: () async {},
        child: const Scaffold(body: Text('content')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(kDevBannerCopy), findsOneWidget);
    expect(find.textContaining('sync'), findsNothing);
    expect(find.byKey(WebDevBanner.dismissButtonKey), findsNothing);

    await tester.pumpWidget(_localizedApp(
      WebGuardrails(
        showBanner: true,
        webSyncEnabled: true,
        onWipe: () async {},
        child: const Scaffold(body: Text('content')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(kSyncedBannerCopy), findsOneWidget);
    expect(find.textContaining('not for real data'), findsNothing,
        reason: 'a sync-enabled build is for real data');
    expect(find.byKey(WebDevBanner.dismissButtonKey), findsOneWidget);
  });

  testWidgets('sync-on browser notice is dismissible for the session only',
      (tester) async {
    await tester.pumpWidget(_localizedApp(
      WebGuardrails(
        key: const ValueKey('first-mount'),
        showBanner: true,
        webSyncEnabled: true,
        onWipe: () async {},
        child: const Scaffold(body: Text('content')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(kSyncedBannerCopy), findsOneWidget);

    await tester.tap(find.byKey(WebDevBanner.dismissButtonKey));
    await tester.pumpAndSettle();
    expect(find.text(kSyncedBannerCopy), findsNothing);
    expect(find.text('content'), findsOneWidget);

    // A fresh mount (a reload) brings the notice back — the dismissal was
    // never persisted.
    await tester.pumpWidget(_localizedApp(
      WebGuardrails(
        key: const ValueKey('second-mount'),
        showBanner: true,
        webSyncEnabled: true,
        onWipe: () async {},
        child: const Scaffold(body: Text('content')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(kSyncedBannerCopy), findsOneWidget);
  });

  testWidgets('banner renders when shown, absent when not', (tester) async {
    var wipes = 0;
    await tester.pumpWidget(
      _localizedApp(
        WebGuardrails(
          showBanner: true,
          onWipe: () async => wipes++,
          child: const Scaffold(body: Text('content')),
        ),
      ),
    );
    expect(find.text(kDevBannerCopy), findsOneWidget);
    expect(find.text('content'), findsOneWidget);

    await tester.pumpWidget(
      _localizedApp(
        WebGuardrails(
          showBanner: false,
          onWipe: () async => wipes++,
          child: const Scaffold(body: Text('content')),
        ),
      ),
    );
    expect(find.text(kDevBannerCopy), findsNothing);
    expect(wipes, 0);
  });

  testWidgets('wipe requires explicit confirmation naming the consequence',
      (tester) async {
    var wipes = 0;
    await tester.pumpWidget(
      _localizedApp(
        WebGuardrails(
          showBanner: true,
          onWipe: () async => wipes++,
          child: const Scaffold(body: Text('content')),
        ),
      ),
    );

    await tester.tap(find.byKey(WebDevBanner.wipeButtonKey));
    await tester.pumpAndSettle();

    // The confirmation names that the erase is unrecoverable.
    expect(
      find.textContaining('cannot be undone'),
      findsOneWidget,
    );

    // Cancel does not wipe.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(wipes, 0);

    // Confirm does.
    await tester.tap(find.byKey(WebDevBanner.wipeButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('web-wipe-confirm')));
    await tester.pumpAndSettle();
    expect(wipes, 1);
    expect(find.text('All local data erased.'), findsOneWidget);
  });

  testWidgets('first-run acknowledgment: blocking, single acknowledge persists',
      (tester) async {
    var acknowledged = 0;
    var persisted = false;
    await tester.pumpWidget(
      _localizedApp(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  final needed = await showWebFirstRunAcknowledgment(
                    context,
                    alreadyAcknowledged: false,
                    onAcknowledged: () async {
                      persisted = true;
                    },
                  );
                  if (needed) acknowledged++;
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    // Dialog is up and cannot be dismissed by tapping the barrier.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('I understand'), findsOneWidget);

    await tester.tap(find.byKey(const Key('web-acknowledge')));
    await tester.pumpAndSettle();
    expect(acknowledged, 1);
    expect(persisted, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('first-run acknowledgment for a sync-enabled build tells the '
      'browser-storage story, not "not for real data"', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showWebFirstRunAcknowledgment(
                  context,
                  alreadyAcknowledged: false,
                  webSyncEnabled: true,
                  onAcknowledged: () async {},
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Using lunarlog in this browser'), findsOneWidget);
    expect(find.textContaining('unencrypted copy'), findsOneWidget);
    expect(find.textContaining('Signing out removes the copy'), findsOneWidget);
    expect(find.textContaining('not for real data'), findsNothing);
  });

  testWidgets('already-acknowledged install skips the dialog', (tester) async {
    var acknowledged = 0;
    await tester.pumpWidget(
      _localizedApp(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  final needed = await showWebFirstRunAcknowledgment(
                    context,
                    alreadyAcknowledged: true,
                    onAcknowledged: () async {},
                  );
                  if (needed) acknowledged++;
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(acknowledged, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('Issue #17 R11: delete never ships on web', () {
    testWidgets('showExportAndDelete: false hides the delete tile even with '
        'an AccountDeletionService present; the null default (this VM test '
        'platform, i.e. not web) shows it', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      final deletion = _FakeAccountDeletionService();

      await tester.pumpWidget(
        MaterialApp(
          // Issue #268: MfaSettingsSection renders whenever AccountSection
          // is signed-in — and in a flag-on build calls
          // AppLocalizations.of immediately. This test run is flag-off
          // (#738 default), where the section self-hides; the delegates
          // stay so a flag-on parameterization of this harness needs no
          // second change.
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: controller),
              Provider<AccountDeletionService>.value(value: deletion),
            ],
            child: const Scaffold(
              body: SingleChildScrollView(
                child: AccountSection(showExportAndDelete: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-delete')), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: controller),
              Provider<AccountDeletionService>.value(value: deletion),
            ],
            child: const Scaffold(
              body: SingleChildScrollView(child: AccountSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-delete')), findsOneWidget);
    });
  });
}

class _FakeAccountDeletionService implements AccountDeletionService {
  @override
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {}
}
