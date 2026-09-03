/// Shared widget-test pumping helpers (U6).
library;

import 'package:flutter_test/flutter_test.dart';

/// Drift's in-memory database answers asynchronously, so a bare
/// `pumpAndSettle` can exit before the last repository/stream hop lands.
/// Gives the event loop several turns to drain.
Future<void> drainIsolateTraffic(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }
}
