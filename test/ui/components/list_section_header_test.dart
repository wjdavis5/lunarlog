/// The shared section title is a heading to a screen reader, and stays out
/// of the label of the control beneath it.
///
/// Before this, the title was plain text. With one tile in a section the
/// two were merged: Settings' Health section was read as one button,
/// "Health, Health Connect sync, Choose which profile's data may sync to
/// Health Connect", and no section title could be reached with heading
/// navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/components/list_section_header.dart';
import 'package:lunarlog/ui/components/settings_section.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: ListView(children: [child])),
);

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

  testWidgets('a single tile beneath the title keeps its own label, and is '
      'not a heading', (tester) async {
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

    final tile = tester.getSemantics(find.byType(ListTile));
    expect(
      tile,
      isSemantics(
        label: 'Health Connect sync\nChoose a profile',
        isHeader: false,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Health')),
      isSemantics(label: 'Health', isHeader: true, hasTapAction: false),
    );

    await tester.tap(find.text('Health Connect sync'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('with several tiles the title is still one heading, and no '
      'tile is', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        SettingsSection(
          id: 'data',
          title: 'Your data',
          children: [
            ListTile(title: const Text('Export my data'), onTap: () {}),
            ListTile(title: const Text('Import from file'), onTap: () {}),
          ],
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Your data')),
      isSemantics(label: 'Your data', isHeader: true),
    );
    for (final title in ['Export my data', 'Import from file']) {
      expect(
        tester.getSemantics(find.widgetWithText(ListTile, title)),
        isSemantics(label: title, isHeader: false, hasTapAction: true),
      );
    }
    handle.dispose();
  });
}
