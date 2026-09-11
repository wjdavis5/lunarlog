/// Unit tests for LLHaptics (Issue #474): selection, action, and destructive
/// haptic feedback triggers with exception guards.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/ui/theme/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<String> hapticCalls = [];

  setUp(() {
    hapticCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticCalls.add(call.arguments as String? ?? 'vibrate');
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('LLHaptics (Issue #474)', () {
    test('selection triggers HapticFeedback.selectionClick', () async {
      LLHaptics.selection();
      expect(hapticCalls, contains('HapticFeedbackType.selectionClick'));
    });

    test('action triggers HapticFeedback.mediumImpact', () async {
      LLHaptics.action();
      expect(hapticCalls, contains('HapticFeedbackType.mediumImpact'));
    });

    test('destructive triggers HapticFeedback.heavyImpact', () async {
      LLHaptics.destructive();
      expect(hapticCalls, contains('HapticFeedbackType.heavyImpact'));
    });

    test('defensively catches platform exceptions without throwing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        throw PlatformException(code: 'UNAVAILABLE', message: 'Haptics not supported');
      });

      expect(() => LLHaptics.selection(), returnsNormally);
      expect(() => LLHaptics.action(), returnsNormally);
      expect(() => LLHaptics.destructive(), returnsNormally);
    });
  });
}
