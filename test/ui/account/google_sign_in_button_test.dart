// Regression coverage for Issue #1239: the Google sign-in button announced
// as a button but its single semantics node carried no SemanticsAction.tap —
// the ExcludeSemantics wrapper strips the InkWell's own semantics — so a
// TalkBack/VoiceOver double-tap had nothing to dispatch and Google sign-in
// was unactivatable via the accessibility tree. Probe style mirrors the
// Issue #1196 group in test/ui/content/cycle_literacy_article_sheet_test.dart.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/google_sign_in_button.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

void main() {
  group('Issue #1239 Google button semantics activation', () {
    // Captured inside the tree, so the walk below finds the node without
    // hard-coding English copy.
    var capturedLabel = '';

    Future<void> pumpButton(
      WidgetTester tester, {
      VoidCallback? onPressed,
    }) async {
      capturedLabel = '';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) {
                  capturedLabel = AppLocalizations.of(
                    context,
                  ).accountGoogleButtonLabel;
                  return GoogleSignInButton(onPressed: onPressed);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(capturedLabel, isNotEmpty);
    }

    /// Walks the real SemanticsOwner tree — the same tree TalkBack and
    /// VoiceOver read — collecting every node.
    List<SemanticsNode> walkSemanticsTree(WidgetTester tester) {
      final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;
      expect(owner.rootSemanticsNode, isNotNull);
      final nodes = <SemanticsNode>[];
      void walk(SemanticsNode node) {
        nodes.add(node);
        for (final child
            in node.debugListChildrenInOrder(
              DebugSemanticsDumpOrder.traversalOrder,
            )) {
          walk(child);
        }
      }

      walk(owner.rootSemanticsNode!);
      return nodes;
    }

    /// The one node that announces the button's localized label.
    SemanticsNode announcedNode(WidgetTester tester) {
      final matches =
          walkSemanticsTree(tester)
              .where((node) => node.getSemanticsData().label == capturedLabel)
              .toList();
      expect(
        matches,
        hasLength(1),
        reason: 'exactly one semantics node must announce "$capturedLabel" — '
            'the ExcludeSemantics wrapper strips the InkWell below it, so no '
            'second node may duplicate the announcement',
      );
      return matches.single;
    }

    testWidgets(
      'the announced node carries the tap action and performing it fires '
      'onPressed (SemanticsOwner walk, no pointer taps)',
      (tester) async {
        var pressed = 0;
        final semantics = tester.ensureSemantics();

        await pumpButton(tester, onPressed: () => pressed++);

        final node = announcedNode(tester);
        final data = node.getSemanticsData();
        // Regression assertion (Issue #1239): the announced node must be
        // activatable — pre-fix it announced button: true with no tap
        // action (actionsBitmask == 0), so a double-tap did nothing.
        expect(
          data.hasAction(SemanticsAction.tap),
          isTrue,
          reason: '"$capturedLabel" must support SemanticsAction.tap',
        );
        expect(
          data.flagsCollection.isButton,
          isTrue,
          reason: '"$capturedLabel" must stay flagged as a button',
        );
        expect(
          data.flagsCollection.isEnabled,
          Tristate.isTrue,
          reason: '"$capturedLabel" must announce enabled while '
              'onPressed != null',
        );

        // The activation itself: dispatch exactly what a TalkBack/VoiceOver
        // double-tap dispatches — SemanticsAction.tap on the semantics node
        // through SemanticsOwner.performAction (mirrors flutter_test's own
        // SemanticsController.performAction; no pointer events).
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(pressed, 1);

        // Disposed in the body, not via addTearDown: flutter_test verifies
        // handles are closed before tearDown callbacks run.
        semantics.dispose();
      },
    );

    testWidgets(
      'the disabled button keeps its announcement and button flag but '
      'offers no tap action to dispatch',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await pumpButton(tester);

        final node = announcedNode(tester);
        final data = node.getSemanticsData();
        expect(
          data.flagsCollection.isButton,
          isTrue,
          reason: '"$capturedLabel" stays a button while disabled',
        );
        expect(
          data.flagsCollection.isEnabled,
          Tristate.isFalse,
          reason: 'a null onPressed must announce disabled',
        );
        expect(
          data.hasAction(SemanticsAction.tap),
          isFalse,
          reason: 'a disabled button must not offer SemanticsAction.tap — '
              "mirroring the InkWell's null onTap",
        );

        semantics.dispose();
      },
    );
  });
}
