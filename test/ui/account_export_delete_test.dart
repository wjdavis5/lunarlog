/// U1 (R13/R14) widget test: the account section shows the "Export data"
/// and "Delete account" tiles for a signed-in operator, hosted in the real
/// app shell the way account_test hosts it.
///
/// UI-flow tests for the share-success path, temp-file cleanup through the
/// UI, and the delete-confirmation flow are deferred: both a hand-rolled
/// provider harness and this app-shell harness crash in the test framework
/// once the delete dialogs/snackbars run (disposed-notifier during build,
/// wrong-build-scope, Overlay deactivate asserts). Findings and candidate
/// approaches are recorded in the run handoff; the behavior those tests
/// would pin is covered at the service level by
/// `test/data/export_service_test.dart`,
/// `test/data/supabase_account_deletion_test.dart`, and
/// `test/data/account_deletion_test.dart`, and the file/cleanup pipeline
/// by `test/data/export_test.dart`.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

import '../support/fake_auth_service.dart';

Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('settings shows the export and delete tiles when signed in',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final auth = FakeAuthService();
    try {
      await DriftProfilesRepository(db.storage)
          .create(displayName: 'Alex', isMinor: false);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(
              id: 'u1', email: 'a@b.c', providers: [AuthProviders.email]));
      await tester.pumpWidget(
        LunarLogApp(
          db: db,
          authService: auth,
          resetDevice: () async {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(key('account-export'), findsOneWidget);
      expect(key('account-delete'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
      await auth.dispose();
    }
  });
}
