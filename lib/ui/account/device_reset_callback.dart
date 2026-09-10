/// The device reset (KTD16) as the widget tree sees it.
///
/// Moved here from `lib/app_lifecycle.dart` (issue #23): the composition
/// root only *provides* this callback, while the account UI
/// (`account_section.dart`, `account_mismatch_screen.dart`) is what consumes
/// it via `context.read<DeviceResetCallback?>()`. Provided by [LunarLogRoot]
/// so any screen can call it without knowing the root. Null in harnesses
/// that mount `LunarLogApp` directly without passing one.
library;

import 'dart:async';

typedef DeviceResetCallback = Future<void> Function();
