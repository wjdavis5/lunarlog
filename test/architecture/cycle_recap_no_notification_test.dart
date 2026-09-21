/// Issue #852's two hard product rules, enforced as guards rather than
/// prose:
///
/// 1. **The cycle-end recap schedules no notification of any kind.** The
///    recap is in-app only by decision — a push about a cycle completing is
///    a health disclosure on a lock screen, exactly what issue #844 removed
///    from the reminder action labels. Reusing
///    `statistic_change.dart`'s pure detection logic is deliberately fine
///    (it is data, not a scheduler), so this guard forbids only the
///    *scheduling* surfaces: the `flutter_local_notifications` plugin, the
///    reminder scheduler/coordinator, and any `.schedule(`/`zonedSchedule`
///    call.
/// 2. **No streaks, badges, or achievements, ever** (reaffirmed on #852) —
///    a health app that gamifies logging punishes the weeks someone needs
///    it least. Guarded over the insights layer.
///
/// Detection strips comments first, so a doc comment that *says* "no
/// streaks" (as the feature's own do) cannot trip its own guard — the same
/// care `health_sync_binding_scope_test.dart` takes. Falsification coverage
/// is included for both detectors.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The files that make up the recap feature (issue #852): the pure
/// derivation, the card, and the tab that mounts it.
const List<String> _recapFiles = [
  'lib/domain/insights/cycle_recap.dart',
  'lib/ui/insights/cycle_recap_card.dart',
  'lib/ui/insights/analysis_tab.dart',
];

/// Surfaces that actually schedule a notification. The recap may reuse
/// `statistic_change.dart` (pure detection) but must never reach one of
/// these.
const List<String> _forbiddenSchedulingTokens = [
  'flutter_local_notifications',
  'ReminderScheduler',
  'NotificationScheduler',
  'ReminderCoordinator',
  'notification_scheduler',
  'reminder_scheduler',
  'reminder_coordinator',
  'zonedSchedule',
  '.schedule(',
];

/// Removes whole-line `//`/`///` comments so explanatory prose cannot trip
/// either detector. The recaps' code style keeps comments on their own
/// lines; this is intentionally conservative rather than a full lexer
/// (a `//` inside a string literal in these three files does not exist).
String _stripLineComments(String source) => source
    .split('\n')
    .where((line) {
      final trimmed = line.trimLeft();
      return !trimmed.startsWith('//');
    })
    .join('\n');

List<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith('.g.dart'))
    .toList();

void main() {
  test('the recap feature schedules no notification', () {
    for (final path in _recapFiles) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path should exist');
      final code = _stripLineComments(file.readAsStringSync());
      for (final token in _forbiddenSchedulingTokens) {
        expect(
          code.contains(token),
          isFalse,
          reason: 'issue #852 is in-app only: $path references "$token", a '
              'notification-scheduling surface. The recap must not schedule '
              'anything. If a fact is needed from the #178 statistic-change '
              'module, reuse its pure logic (statistic_change.dart), never '
              'the scheduler.',
        );
      }
    }
  });

  test('no streak/badge/achievement concept exists in the insights layer', () {
    final files = [
      ..._dartFilesUnder('lib/domain/insights'),
      ..._dartFilesUnder('lib/ui/insights'),
    ];
    expect(files, isNotEmpty, reason: 'scanned zero insights files');
    final offenders = <String>[];
    for (final file in files) {
      final code = _stripLineComments(file.readAsStringSync()).toLowerCase();
      for (final token in const ['streak', 'achievement']) {
        if (code.contains(token)) {
          offenders.add('${file.path}: "$token"');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'issue #852 reaffirms there are no streaks or achievements; '
            'the insights layer gained:\n${offenders.join('\n')}');
  });

  // --- falsification coverage: a detector that matches nothing proves
  // nothing ---

  test('the scheduling detector catches a scheduled call', () {
    const source = '''
class Recap {
  void go(NotificationScheduler s) => s.schedule(1, 'x');
}
''';
    final code = _stripLineComments(source);
    expect(
      _forbiddenSchedulingTokens.any(code.contains),
      isTrue,
      reason: 'a real scheduler reference must be caught',
    );
  });

  test('the scheduling detector catches a flutter_local_notifications '
      'import', () {
    const source = "import 'package:flutter_local_notifications/"
        "flutter_local_notifications.dart';";
    expect(
      _forbiddenSchedulingTokens.any(_stripLineComments(source).contains),
      isTrue,
    );
  });

  test('the streak detector ignores a comment that mentions streaks', () {
    const source = '''
/// No streaks, badges, or achievements, ever.
class Recap {
  final int cycleNumber = 1;
}
''';
    expect(_stripLineComments(source).toLowerCase().contains('streak'), isFalse,
        reason: "the feature's own doc comment must not trip the guard");
  });

  test('the streak detector catches a real streak field', () {
    const source = 'class Recap { final int streakCount = 0; }';
    expect(
      _stripLineComments(source).toLowerCase().contains('streak'),
      isTrue,
    );
  });
}
