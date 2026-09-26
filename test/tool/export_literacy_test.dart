import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/export_literacy.dart';

void main() {
  test('committed literacy export matches the library byte for byte', () {
    final file = File(kLiteracyExportPath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'The site export is missing. Run `dart run tool/export_literacy.dart` '
          'and commit $kLiteracyExportPath.',
    );
    expect(
      file.readAsStringSync(),
      buildLiteracyExportJson(),
      reason:
          'The committed site export is stale. Run '
          '`dart run tool/export_literacy.dart` and commit the result.',
    );
  });
}
