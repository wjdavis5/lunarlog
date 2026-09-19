/// Widget tests for the reusable, searchable, collapsible tag picker
/// (Issue #234). Exercises a small, real slice of the taxonomy
/// (`TagCategory.pain` — attested; `TagCategory.sleepQuality` — unverified)
/// rather than the full ~110-code list, so tests stay fast and focused.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/ui/components/category_picker.dart';
import 'package:lunarlog/ui/components/tag_icons.dart';

String _label(TagCategory category) => switch (category) {
      TagCategory.pain => 'Pain',
      TagCategory.sleepQuality => 'Sleep quality',
      TagCategory.hotFlashes => 'Hot flashes',
      _ => category.wireName,
    };

Widget _harness({
  List<TagCategory> categories = const [TagCategory.pain, TagCategory.sleepQuality],
  Set<String> selected = const {},
  required ValueChanged<String> onToggle,
  List<String> recentCodes = const [],
  bool enabled = true,
  List<Widget> Function(TagCategory)? trailingBuilder,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CategoryPicker(
          categories: categories,
          categoryLabel: _label,
          selected: selected,
          onToggle: onToggle,
          recentCodes: recentCodes,
          enabled: enabled,
          unverifiedNote: 'Unverified — pin before shipping',
          trailingBuilder: trailingBuilder,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders every attested category chip and its heading',
      (tester) async {
    await tester.pumpWidget(_harness(onToggle: (_) {}));

    expect(find.text('Pain'), findsOneWidget);
    for (final tag in kTagTaxonomy.where((t) => t.category == TagCategory.pain)) {
      expect(find.text(tag.display), findsOneWidget);
    }
  });

  testWidgets('an unverified category shows its heading and the caption, '
      'no chips', (tester) async {
    await tester.pumpWidget(_harness(onToggle: (_) {}));

    expect(find.text('Sleep quality'), findsOneWidget);
    expect(find.text('Unverified — pin before shipping'), findsOneWidget);
  });

  testWidgets('tapping an unselected chip calls onToggle with its code',
      (tester) async {
    String? toggled;
    await tester.pumpWidget(_harness(onToggle: (code) => toggled = code));

    await tester.tap(find.text('Cramps'));
    expect(toggled, 'cramps');
  });

  testWidgets('a selected code renders its chip as selected', (tester) async {
    await tester.pumpWidget(
      _harness(selected: const {'cramps'}, onToggle: (_) {}),
    );
    final chip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('Cramps'), matching: find.byType(FilterChip)),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('disabled: chips do not respond to taps', (tester) async {
    var called = false;
    await tester.pumpWidget(
      _harness(enabled: false, onToggle: (_) => called = true),
    );
    final chip = tester.widget<FilterChip>(
      find.ancestor(of: find.text('Cramps'), matching: find.byType(FilterChip)),
    );
    expect(chip.onSelected, isNull);
    expect(called, isFalse);
  });

  group('search', () {
    testWidgets('filters chips across categories as the user types',
        (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));

      await tester.enterText(
        find.byKey(const ValueKey('category-picker-search')),
        'head',
      );
      await tester.pumpAndSettle();

      expect(find.text('Headache'), findsOneWidget);
      expect(find.text('Cramps'), findsNothing);
    });

    testWidgets('hides an attested category entirely once nothing in it '
        'matches', (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));

      await tester.enterText(
        find.byKey(const ValueKey('category-picker-search')),
        'zzz-no-match',
      );
      await tester.pumpAndSettle();

      expect(find.text('Pain'), findsNothing);
      expect(find.text('Cramps'), findsNothing);
    });

    testWidgets('hides unverified categories entirely while searching',
        (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));

      await tester.enterText(
        find.byKey(const ValueKey('category-picker-search')),
        'head',
      );
      await tester.pumpAndSettle();

      expect(find.text('Sleep quality'), findsNothing);
      expect(find.text('Unverified — pin before shipping'), findsNothing);
    });

    testWidgets('the clear button resets the search and restores every '
        'category', (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));

      await tester.enterText(
        find.byKey(const ValueKey('category-picker-search')),
        'head',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-picker-search-clear')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('category-picker-search-clear')));
      await tester.pumpAndSettle();

      expect(find.text('Cramps'), findsOneWidget);
      expect(find.text('Sleep quality'), findsOneWidget);
      expect(find.byKey(const ValueKey('category-picker-search-clear')), findsNothing);
    });

    testWidgets('the search field is disabled when the picker is disabled',
        (tester) async {
      await tester.pumpWidget(_harness(enabled: false, onToggle: (_) {}));
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('category-picker-search')),
      );
      expect(field.enabled, isFalse);
    });
  });

  group('collapsible sections', () {
    testWidgets('tapping the header collapses and re-expanding restores '
        'the chips', (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));
      expect(find.text('Cramps'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('category-picker-header-pain')));
      await tester.pumpAndSettle();
      expect(find.text('Cramps'), findsNothing);
      // The heading itself is still there — collapsing hides chips, not
      // the section.
      expect(find.text('Pain'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('category-picker-header-pain')));
      await tester.pumpAndSettle();
      expect(find.text('Cramps'), findsOneWidget);
    });

    testWidgets('a collapsed category still expands automatically while '
        'searching', (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));
      await tester.tap(find.byKey(const ValueKey('category-picker-header-pain')));
      await tester.pumpAndSettle();
      expect(find.text('Cramps'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('category-picker-search')),
        'cramps',
      );
      await tester.pumpAndSettle();
      expect(find.text('Cramps'), findsOneWidget);
    });

    testWidgets('the header does not collapse when the picker is disabled',
        (tester) async {
      await tester.pumpWidget(_harness(enabled: false, onToggle: (_) {}));
      await tester.tap(find.byKey(const ValueKey('category-picker-header-pain')));
      await tester.pumpAndSettle();
      expect(find.text('Cramps'), findsOneWidget);
    });
  });

  group('Recent row', () {
    testWidgets('renders nothing when there are no recents', (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));
      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('shows a chip per recent code, most-recent-first order '
        'preserved', (tester) async {
      await tester.pumpWidget(
        _harness(
          recentCodes: const ['headache', 'cramps'],
          onToggle: (_) {},
        ),
      );

      expect(find.text('Recent'), findsOneWidget);
      // Both the Recent row's own chip and the main Pain-section chip
      // render "Headache"/"Cramps" — exactly two of each is expected.
      expect(find.text('Headache'), findsNWidgets(2));
      expect(find.text('Cramps'), findsNWidgets(2));
    });

    testWidgets('drops an already-selected code from the Recent row '
        '(no duplicate chip for the same toggle)', (tester) async {
      await tester.pumpWidget(
        _harness(
          selected: const {'cramps'},
          recentCodes: const ['cramps', 'headache'],
          onToggle: (_) {},
        ),
      );

      // "Cramps" renders once (its own category chip only); "Headache"
      // renders twice (Recent row + its category chip).
      expect(find.text('Cramps'), findsOneWidget);
      expect(find.text('Headache'), findsNWidgets(2));
    });

    testWidgets('is hidden entirely while searching', (tester) async {
      await tester.pumpWidget(
        _harness(recentCodes: const ['cramps'], onToggle: (_) {}),
      );
      expect(find.text('Recent'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('category-picker-search')),
        'head',
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('tapping a Recent chip calls onToggle with its code',
        (tester) async {
      String? toggled;
      await tester.pumpWidget(
        _harness(
          recentCodes: const ['cramps'],
          onToggle: (code) => toggled = code,
        ),
      );
      // Two "Cramps" chips render (Recent + Pain section); tap the first.
      await tester.tap(find.text('Cramps').first);
      expect(toggled, 'cramps');
    });

    testWidgets('an unknown recent code (not in the taxonomy) is silently '
        'dropped rather than crashing', (tester) async {
      await tester.pumpWidget(
        _harness(recentCodes: const ['not-a-real-code'], onToggle: (_) {}),
      );
      expect(find.text('Recent'), findsNothing);
    });
  });

  testWidgets('trailingBuilder content renders under its named category',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        onToggle: (_) {},
        trailingBuilder: (category) => category == TagCategory.pain
            ? [const Text('pain-trailing-marker')]
            : const [],
      ),
    );
    expect(find.text('pain-trailing-marker'), findsOneWidget);
  });

  group('option icons (Issue #818)', () {
    test('tagOptionIcon maps a curated option and returns null for the '
        'deliberately uniconed ones', () {
      expect(tagOptionIcon('cramps'), Icons.bolt);
      // Moods have no unambiguous symbol — never a placeholder.
      expect(tagOptionIcon('happy'), isNull);
      expect(tagOptionIcon('not-a-real-code'), isNull);
    });

    testWidgets('an option with an unambiguous symbol renders its icon',
        (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('category-picker-tag-cramps')),
          matching: find.byIcon(Icons.bolt),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an option without an unambiguous symbol renders text-only '
        'with no placeholder glyph', (tester) async {
      await tester.pumpWidget(
        _harness(categories: const [TagCategory.feelings], onToggle: (_) {}),
      );

      final chip = find.byKey(const ValueKey('category-picker-tag-happy'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.byType(Icon)),
        findsNothing,
        reason: 'no icon (and no label_outline stand-in) belongs on an '
            'option whose symbol is not unambiguous',
      );
    });

    testWidgets('the icon does not become a second announced element and '
        'does not change the spoken label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness(onToggle: (_) {}));

      expect(find.bySemanticsLabel('Pain, Cramps'), findsOneWidget);
      expect(find.bySemanticsLabel('Pain, Headache'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('adding the icon does not shrink the chip tap target',
        (tester) async {
      await tester.pumpWidget(_harness(onToggle: (_) {}));

      final size = tester.getSize(
        find.byKey(const ValueKey('category-picker-tag-cramps')),
      );
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'MaterialTapTargetSize.padded must survive the avatar');
    });

    testWidgets('a selected option still carries the non-colour checkmark '
        'cue, so the icon never makes selection colour-only', (tester) async {
      await tester.pumpWidget(
        _harness(selected: const {'cramps'}, onToggle: (_) {}),
      );

      final chip = tester.widget<FilterChip>(
        find.byKey(const ValueKey('category-picker-tag-cramps')),
      );
      expect(chip.selected, isTrue);
      expect(chip.showCheckmark, isNot(false),
          reason: 'the painted check (plus the fill/border) keeps selection '
              'distinguishable without colour; an avatar must never suppress it');
    });

    testWidgets('a Recent-row shortcut carries the same option icon',
        (tester) async {
      await tester.pumpWidget(
        _harness(recentCodes: const ['cramps'], onToggle: (_) {}),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('category-picker-recent-cramps')),
          matching: find.byIcon(Icons.bolt),
        ),
        findsOneWidget,
      );
    });
  });
}
