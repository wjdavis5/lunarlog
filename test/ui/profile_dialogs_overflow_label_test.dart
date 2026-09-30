/// Issue #1230: the Edit profile sheet's first outlined field (Name) sits
/// flush against the top of its `SingleChildScrollView`, and the outlined
/// floating label paints half of its line box *above* the field's top
/// border (Flutter's `outlinedFloatingY` in input_decorator.dart). Since
/// #1217 capped the sheet with `useSafeArea: true`, a form taller than the
/// sheet overflows the viewport, `RenderSingleChildViewport` starts
/// clipping, and the label's top half is cut off at scroll offset 0. The
/// fix gives the scroll content a text-scale-aware top headroom
/// (`8 * textScaler.scale(1)`) so the label is inside the viewport at
/// every text size. Mirrors `profile_dialogs_safe_area_test.dart`'s
/// harness (same QA surface, same fake modes repository).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/profile_dialogs.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

class _FakeModesRepository implements ProfileModesRepository {
  _FakeModesRepository(this.row);
  ProfileLifecycleMode? row;
  @override
  Future<ProfileLifecycleMode?> find(String profileId) async => row;
  @override
  Stream<ProfileLifecycleMode?> watch(String profileId) => Stream.value(row);
  @override
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? estimatedDueDate,
    String? postpartumBirthDate,
    String? birthControlMethod,
  }) async {}
}

/// A tracked method ('pill') makes the #1203 "Started on" field show,
/// which is what pushes Maya's form past the capped sheet on the QA
/// device; null (Edge's no-method answer) keeps it hidden so a roomy
/// surface can host a fitting form.
ProfileLifecycleMode? _row(String? birthControlMethod) => (
      mode: LifecycleMode.tracking,
      modeStartedOn: null,
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: birthControlMethod,
      birthControlStartedOn: birthControlMethod == null ? null : '2026-08-15',
      birthControlStoppedOn: null,
    );

Profile _profile() => Profile(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q8R9',
      displayName: 'Maya',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _pumpEditSheet(
  WidgetTester tester, {
  required String? birthControlMethod,
  required double textScale,
  Size surface = const Size(402, 874),
}) async {
  // The QA surface from the issue (iPhone 17 Pro, logical points) with its
  // status-bar / Dynamic Island inset. dpr 1.0 keeps the FakeViewPadding
  // values logical, matching a11y_pass_test.dart's setup.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = surface;
  tester.view.padding = const FakeViewPadding(top: 59.0);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() => tester.platformDispatcher.clearTextScaleFactorTestValue());

  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ProfileModesRepository?>.value(
          value: _FakeModesRepository(_row(birthControlMethod))),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showProfileEditDialog(context, existing: _profile()),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The scroll viewport and the floated 'Name' label's painted rects. The
/// label's paint transform carries the floated position (see
/// input_decorator.dart's `_labelTransform` and
/// `_RenderDecoration.applyPaintTransform`), so these rects are exactly
/// what the viewport's clip does or doesn't cut.
Rect _scrollViewRect(WidgetTester tester) {
  expect(find.byType(SingleChildScrollView), findsOneWidget,
      reason: 'the sheet owns the only scroll view in this tree');
  return tester.getRect(find.byType(SingleChildScrollView));
}

/// Whether [inner] sits fully inside [outer], with the one edge that
/// matters most (the viewport's top — the clipping edge) named in the
/// failure output.
bool _fullyInside(Rect outer, Rect inner) =>
    inner.top >= outer.top &&
    inner.bottom <= outer.bottom &&
    inner.left >= outer.left &&
    inner.right <= outer.right;

void main() {
  testWidgets(
      'the Name floating label stays inside the scroll viewport when the '
      'form overflows at the default text scale (issue #1230)',
      (tester) async {
    await _pumpEditSheet(tester,
        birthControlMethod: 'pill', textScale: 1.0);

    final viewport = _scrollViewRect(tester);
    final form = tester.getRect(find.byType(Form));
    // Guard the premise: the form really does overflow the viewport here
    // (the tracked method's "Started on" field plus the capped sheet), so
    // the viewport's clip is active and the assertion below is pinning the
    // #1230 scenario, not a short sheet that never clips.
    expect(form.bottom, greaterThan(viewport.bottom),
        reason: 'the Pill profile\'s form must overflow the capped sheet '
            'for this to exercise the clipping path');

    final label = tester.getRect(find.text('Name'));
    expect(_fullyInside(viewport, label), isTrue,
        reason: 'the floated Name label paints half of its line box above '
            'the field\'s top border; with the form flush against the '
            'viewport at scroll offset 0 that overhang is clipped, and '
            'before the fix ${viewport.top - label.top}dp of the label sat '
            'above the viewport top');
  });

  testWidgets(
      'the same containment holds at an accessibility text scale, where '
      'every profile\'s form overflows (issue #1230)', (tester) async {
    await _pumpEditSheet(tester, birthControlMethod: 'pill', textScale: 2.0);

    final viewport = _scrollViewRect(tester);
    final form = tester.getRect(find.byType(Form));
    expect(form.bottom, greaterThan(viewport.bottom),
        reason: 'at 2x text the form must overflow for this to exercise '
            'the clipping path');

    final label = tester.getRect(find.text('Name'));
    // A fixed top padding cannot pass this: the label's overhang above the
    // field's top border grows with the text scale (~5.5dp at 1x, ~11dp at
    // 2x), so the headroom has to track the ambient text scaler.
    expect(_fullyInside(viewport, label), isTrue,
        reason: 'the label\'s overhang scales with the text size, so the '
            'scroll content\'s top headroom must scale with it');
  });

  testWidgets(
      'control: a profile whose form still fits keeps the label inside its '
      'non-clipping viewport (issue #1230)', (tester) async {
    // Edge's no-method answer hides the "Started on" field; the roomier
    // surface hosts the form without overflow (the test font runs wider
    // than the QA device's font, which is what pushed the 874-tall surface
    // into overflow for this profile too).
    await _pumpEditSheet(
      tester,
      birthControlMethod: null,
      textScale: 1.0,
      surface: const Size(402, 1100),
    );

    final viewport = _scrollViewRect(tester);
    final form = tester.getRect(find.byType(Form));
    // Guard the premise: no overflow means RenderSingleChildViewport does
    // not clip at all, so the label was never visually cut here — this
    // pins that the added headroom does not push a fitting form into
    // overflow or out of the viewport.
    expect(form.bottom, lessThanOrEqualTo(viewport.bottom),
        reason: 'this control case must be a form that fits the viewport');

    final label = tester.getRect(find.text('Name'));
    expect(_fullyInside(viewport, label), isTrue,
        reason: 'the label must sit inside the viewport on a fitting form '
            'too');
  });
}
