import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/export_help_cards.dart';

void main() {
  test('committed help-card export matches the library byte for byte', () {
    final file = File(kHelpCardsExportPath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'The site export is missing. Run `dart run tool/export_help_cards.dart` '
          'and commit $kHelpCardsExportPath.',
    );
    expect(
      file.readAsStringSync(),
      buildHelpCardsExportJson(),
      reason:
          'The committed site export is stale. Run '
          '`dart run tool/export_help_cards.dart` and commit the result.',
    );
  });
}
