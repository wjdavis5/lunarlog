/// The webapp token export's regeneration runner (issue #1249): writes
/// `webapp/src/theme/tokens.generated.json` from the live app theme.
///
/// Run it with one command from the repo root:
///
/// ```
/// flutter test tool/export_webapp_tokens_generate_test.dart
/// ```
///
/// This file is deliberately outside `test/`, so plain `flutter test` (and
/// therefore every CI shard) never runs it — it writes a file. The CI
/// enforcement is the byte-for-byte freshness test in
/// `test/tool/export_webapp_tokens_test.dart`, which fails whenever this
/// runner should have been run. Same split as
/// `tool/screenshots/render_screens_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'export_webapp_tokens.dart';

void main() {
  test('regenerates the webapp token export', () {
    writeWebappTokensExport();
  });
}
