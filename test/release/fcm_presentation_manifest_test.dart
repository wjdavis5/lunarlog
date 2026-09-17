/// FCM presentation plumbing guard (issue #174). Mirrors
/// `health_connect_manifest_test.dart`'s shape: read the Android manifest
/// and iOS Info.plist as text and assert the invariants the push
/// presentation wiring depends on, since none of it compiles or runs under
/// `flutter test`. The channel-id meta-data is pinned against the Dart
/// constant the scheduler creates the channel with
/// (`kReminderChannelId`), so the manifest copy cannot silently drift from
/// the channel the app actually posts on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart';

import 'repo_text_helpers.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _plistPath = 'ios/Runner/Info.plist';

void main() {
  group('FCM presentation plumbing guard (issue #174)', () {
    late String manifest;
    late String plist;

    setUpAll(() {
      manifest = readRepoFile(_manifestPath);
      plist = readRepoFile(_plistPath);
    });

    test(
        'the manifest pins FCM tray presentations onto the app\'s own '
        'Reminders channel, matching kReminderChannelId exactly',
        () {
      expect(
        manifest,
        contains(
          'android:name="com.google.firebase.messaging.default_notification_channel_id"'),
      );
      expect(
        manifest,
        contains(
            'android:value="$kReminderChannelId"'),
        reason: 'the meta-data must point at the same channel '
            'lib/data/notifications/notification_scheduler.dart creates; a '
            'drift would split caregiver alerts from local reminders into '
            'two channels',
      );
      expect(kReminderChannelId, 'lunarlog_reminders',
          reason: 'renaming the channel id must be a deliberate change that '
              'updates this pin, the manifest, and the scheduler together');
    });

    test(
        'the manifest declares the default FCM notification icon as the '
        'launcher icon the local notifications setup initializes with',
        () {
      expect(
        manifest,
        contains(
          'android:name="com.google.firebase.messaging.default_notification_icon"'),
      );
      // The same resource AndroidInitializationSettings uses in
      // notification_scheduler.dart / push_presentation.dart — this app has
      // no dedicated monochrome drawable, so the launcher icon is the
      // shared small-icon resource by existing convention.
      expect(manifest, contains('@mipmap/ic_launcher'));
    });

    test(
        'ios/Runner/Info.plist declares remote-notification, now backed by '
        'the registered background handler (not an unbacked App Review '
        'query)',
        () {
      expect(plist, contains('<key>UIBackgroundModes</key>'));
      expect(plist, contains('<string>remote-notification</string>'));
      expect(
          plist,
          contains('pushBackgroundMessageHandler'),
          reason: 'the declaration\'s comment must name what backs it — the '
              'handler registered before runApp() in lib/main.dart behind '
              'AppConfig.hasPush (issue #174)');
    });
  });
}
