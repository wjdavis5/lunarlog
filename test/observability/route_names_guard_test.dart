import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/observability/scrub.dart';

void main() {
  group('Route names registry and scrub checks (Issue #205)', () {
    test('all required routes exist and are present in kSentryRouteNames', () {
      const requiredRoutes = [
        kRouteNotificationPreferencesScreen,
        kRouteTransferOwnershipScreen,
        kRouteAcceptInviteSheet,
        kRouteClaimProfileSheet,
        kRouteHelpLibraryScreen,
        kRouteHelpCardSheet,
      ];

      for (final route in requiredRoutes) {
        expect(kSentryRouteNames, contains(route),
            reason: '$route must be registered in kSentryRouteNames');
      }
    });

    test('scrubRouteName preserves all required routes and does not map to unknown', () {
      const requiredRoutes = [
        kRouteNotificationPreferencesScreen,
        kRouteTransferOwnershipScreen,
        kRouteAcceptInviteSheet,
        kRouteClaimProfileSheet,
        kRouteHelpLibraryScreen,
        kRouteHelpCardSheet,
      ];

      for (final route in requiredRoutes) {
        expect(scrubRouteName(route), equals(route),
            reason: '$route must resolve to its named route in scrubRouteName, not unknown');
      }
    });
  });

  group('Static route naming lint guard (Issue #205 AC4)', () {
    test('all MaterialPageRoute and showModalBottomSheet call sites in lib/ui and lib/app.dart specify route settings', () {
      final filesToScan = <File>[
        File('lib/app.dart'),
        ...Directory('lib/ui')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      ];

      expect(filesToScan, isNotEmpty, reason: 'Must scan lib/app.dart and lib/ui');

      final violations = <String>[];

      for (final file in filesToScan) {
        final path = file.path.replaceAll(r'\', '/');
        // lib/ui/routes.dart is the designated factory for buildNamedRoute.
        if (path == 'lib/ui/routes.dart') continue;

        final content = file.readAsStringSync();

        // 1. Check for MaterialPageRoute call sites lacking settings:
        if (content.contains('MaterialPageRoute')) {
          // Look for MaterialPageRoute<...>( or MaterialPageRoute(
          final matches = RegExp(r'MaterialPageRoute(?:<[^>]+>)?\s*\(([\s\S]*?)\)(?:\s*;|\s*,|\s*\))').allMatches(content);
          for (final m in matches) {
            final args = m.group(1) ?? '';
            if (!args.contains('settings:')) {
              violations.add('$path: MaterialPageRoute call site missing settings: argument');
            }
          }
        }

        // 2. Check for showModalBottomSheet call sites lacking routeSettings:
        if (content.contains('showModalBottomSheet')) {
          final matches = RegExp(r'showModalBottomSheet(?:<[^>]+>)?\s*\(([\s\S]*?)\)(?:\s*;|\s*,|\s*\))').allMatches(content);
          for (final m in matches) {
            final args = m.group(1) ?? '';
            if (!args.contains('routeSettings:')) {
              violations.add('$path: showModalBottomSheet call site missing routeSettings: argument');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'All MaterialPageRoute and showModalBottomSheet calls in lib/ui and lib/app.dart must specify settings:/routeSettings:\n${violations.join('\n')}');
    });
  });
}
