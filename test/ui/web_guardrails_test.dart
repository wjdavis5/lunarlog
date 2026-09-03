/// U8 web guardrail tests (KTD9): non-dismissible banner, confirmation-
/// guarded wipe, one-time blocking first-profile acknowledgment.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/ui/web/dev_banner.dart';

const String kSyncedBannerCopy = 'Development build — this browser holds '
    'your synced family data unencrypted. Not for real data.';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('the app wires the wipe to the device reset callback (KTD16)',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    var resets = 0;
    await tester.pumpWidget(LunarLogApp(
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

  testWidgets('banner copy: sync off (the default) never mentions sync; '
      'sync on names the exposure', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WebGuardrails(
        showBanner: true,
        onWipe: () async {},
        child: const Scaffold(body: Text('content')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Development build — not for real data.'),
        findsOneWidget);
    expect(find.textContaining('sync'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: WebGuardrails(
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
      MaterialApp(
        home: WebGuardrails(
          showBanner: true,
          onWipe: () async => wipes++,
          child: const Scaffold(body: Text('content')),
        ),
      ),
    );
    expect(find.text('Development build — not for real data.'),
        findsOneWidget);
    expect(find.text('content'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: WebGuardrails(
          showBanner: false,
          onWipe: () async => wipes++,
          child: const Scaffold(body: Text('content')),
        ),
      ),
    );
    expect(find.text('Development build — not for real data.'),
        findsNothing);
    expect(wipes, 0);
  });

  testWidgets('wipe requires explicit confirmation naming the consequence',
      (tester) async {
    var wipes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WebGuardrails(
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
      MaterialApp(
        home: Scaffold(
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

  testWidgets('already-acknowledged install skips the dialog', (tester) async {
    var acknowledged = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
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
}
