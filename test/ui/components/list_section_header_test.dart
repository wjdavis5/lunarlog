/// The shared section title is a heading to a screen reader, and a
/// Settings section reads title first, then each tile on its own.
///
/// Before this, the title was plain text and the section, being one child
/// of the Settings list, took its first tile into its own node. Settings'
/// Health section was one button the size of the section, "Health, Health
/// Connect sync, Choose which profile's data may sync to Health Connect",
/// and no section title could be reached with heading navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/list_section_header.dart';
import 'package:lunarlog/ui/components/settings_section.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: [child])),
);

/// The labels a screen reader meets under [group], in reading order.
List<String> _labelsInOrder(SemanticsNode group) => [
  for (final node in group.debugListChildrenInOrder(
    DebugSemanticsDumpOrder.traversalOrder,
  ))
    node.label,
];

void main() {
  testWidgets('the title is its own heading node', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const ListSectionHeader(title: 'Health')));

    expect(
      tester.getSemantics(find.text('Health')),
      isSemantics(label: 'Health', isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('a section with one tile reads the title, then the tile: the '
      'tile keeps its own label and is not the size of the section', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _host(
        SettingsSection(
          id: 'health',
          title: 'Health',
          children: [
            ListTile(
              title: const Text('Health Connect sync'),
              subtitle: const Text('Choose a profile'),
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    );

    final heading = tester.getSemantics(find.text('Health'));
    final tile = tester.getSemantics(find.byType(ListTile));
    expect(
      heading,
      isSemantics(label: 'Health', isHeader: true, hasTapAction: false),
    );
    expect(
      tile,
      isSemantics(
        label: 'Health Connect sync\nChoose a profile',
        isHeader: false,
        isButton: true,
        hasTapAction: true,
      ),
    );

    // Siblings in reading order. The title used to sit inside the button,
    // where a screen reader reaches it after the button it heads.
    expect(heading.parent, same(tile.parent));
    expect(_labelsInOrder(tile.parent!), [
      'Health',
      'Health Connect sync\nChoose a profile',
    ]);
    expect(
      tile.rect.height,
      tester.getSize(find.byType(ListTile)).height,
      reason: 'the button is the tile, not the whole section',
    );

    await tester.tap(find.text('Health Connect sync'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a section with several kinds of row reads them in order, '
      'each on its own, under one heading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        SettingsSection(
          id: 'calendar',
          title: 'Calendar',
          children: [
            ListTile(title: const Text('First day of week'), onTap: () {}),
            SwitchListTile(
              title: const Text('Show estimates'),
              value: true,
              onChanged: (_) {},
            ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Measurement units'),
            ),
          ],
        ),
      ),
    );

    final heading = tester.getSemantics(find.text('Calendar'));
    expect(heading, isSemantics(label: 'Calendar', isHeader: true));
    expect(_labelsInOrder(heading.parent!), [
      'Calendar',
      'First day of week',
      'Show estimates',
      'Measurement units',
    ]);
    // The first tile used to be the section's own node, a button holding
    // the title and every later row.
    expect(
      heading.parent,
      isSemantics(label: '', isButton: false, hasTapAction: false),
    );
    for (final title in ['First day of week', 'Show estimates']) {
      expect(
        tester.getSemantics(find.text(title)),
        isSemantics(label: title, isHeader: false, hasTapAction: true),
      );
    }
    handle.dispose();
  });
}
