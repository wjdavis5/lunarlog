/// The platform-safe barrel for the widget data store (issue #141).
///
/// Conditionally selects the real `home_widget` implementation on IO
/// platforms (iOS/Android/desktop) and a throwing stub on web: the plugin's
/// own Dart source imports `dart:io` unconditionally, so a plain import
/// would fail the web build — the same conditional-export discipline the
/// conditional-export seams in `lib/data/db/platform_factory.dart` use.
/// Import THIS file, never the `_io`/`_stub` twins directly.
///
/// Also owns the one platform gate everything else consults:
/// [hasHomeWidgetSurface] — true exactly where a widget surface exists
/// (iOS and Android). Web and desktop get the composition root's null
/// store, the same zero-conditional posture as `NoopReminderScheduler` on
/// platforms without notifications.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

export 'home_widget_data_store_stub.dart'
    if (dart.library.io) 'home_widget_data_store_io.dart';

/// Whether this platform has a widget surface at all.
bool get hasHomeWidgetSurface {
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
      return true;
    case _:
      return false;
  }
}
