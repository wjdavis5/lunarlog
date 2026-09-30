import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/export_webapp_tokens.dart';

void main() {
  test('committed webapp token export matches the theme byte for byte', () {
    final file = File(kWebappTokensExportPath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'The webapp token export is missing. Run '
          '`dart run tool/export_webapp_tokens.dart` and commit '
          '$kWebappTokensExportPath.',
    );
    expect(
      file.readAsStringSync(),
      buildWebappTokensJson(),
      reason:
          'The committed webapp token export is stale relative to the app '
          'theme (lib/ui/theme/). Run '
          '`dart run tool/export_webapp_tokens.dart` and commit the result.',
    );
  });

  test('the export carries both schemes and no translucent colours', () {
    final json = buildWebappTokensJson();
    expect(json, contains('"light"'));
    expect(json, contains('"dark"'));
    // #RRGGBBAA (8 hex digits after #) would mean a translucent scheme role;
    // the M3 scheme the app builds is fully opaque, and the web client's
    // contract assumes it.
    expect(RegExp(r'#[0-9a-f]{8}').hasMatch(json), isFalse);
  });
}
