/// Direct unit coverage for [buildFirebaseOptions] (Issue #5; round-2
/// review #3): the one piece of pure branching logic pulled out of the
/// otherwise plugin-excluded `firebase_push_token_source.dart` (see that
/// file's own doc comment and `tool/quality/exclusions.dart`'s entry for
/// it). Round-1 #10 flagged the coverage exclusion for claiming "no
/// branching worth testing" while hiding the sequencing bugs that shipped
/// in #4/#5; round-2 #3 found that the rewritten rationale went on to claim
/// this exact test existed when it did not. This file makes that claim
/// true.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/firebase_push_token_source.dart';

void main() {
  group('buildFirebaseOptions', () {
    test('isIOS: true selects the iOS apiKey/appId, not the Android pair',
        () {
      final options = buildFirebaseOptions(
        isIOS: true,
        iosApiKey: 'ios-api-key',
        iosAppId: 'ios-app-id',
        androidApiKey: 'android-api-key',
        androidAppId: 'android-app-id',
        senderId: 'sender-1',
        projectId: 'project-1',
      );

      expect(
        options,
        const FirebaseOptions(
          apiKey: 'ios-api-key',
          appId: 'ios-app-id',
          messagingSenderId: 'sender-1',
          projectId: 'project-1',
        ),
      );
    });

    test('isIOS: false selects the Android apiKey/appId, not the iOS pair',
        () {
      final options = buildFirebaseOptions(
        isIOS: false,
        iosApiKey: 'ios-api-key',
        iosAppId: 'ios-app-id',
        androidApiKey: 'android-api-key',
        androidAppId: 'android-app-id',
        senderId: 'sender-1',
        projectId: 'project-1',
      );

      expect(
        options,
        const FirebaseOptions(
          apiKey: 'android-api-key',
          appId: 'android-app-id',
          messagingSenderId: 'sender-1',
          projectId: 'project-1',
        ),
      );
    });

    test('senderId and projectId pass through unchanged on both platforms',
        () {
      final ios = buildFirebaseOptions(
        isIOS: true,
        iosApiKey: 'a',
        iosAppId: 'b',
        androidApiKey: 'c',
        androidAppId: 'd',
        senderId: 'shared-sender',
        projectId: 'shared-project',
      );
      final android = buildFirebaseOptions(
        isIOS: false,
        iosApiKey: 'a',
        iosAppId: 'b',
        androidApiKey: 'c',
        androidAppId: 'd',
        senderId: 'shared-sender',
        projectId: 'shared-project',
      );

      expect(ios.messagingSenderId, 'shared-sender');
      expect(ios.projectId, 'shared-project');
      expect(android.messagingSenderId, 'shared-sender');
      expect(android.projectId, 'shared-project');
    });
  });
}
