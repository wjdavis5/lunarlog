/// The shell's public tab-switch seam (issue #313): lets any widget mounted
/// inside [AppShell]'s body switch the shell to a different tab without
/// reaching into `app_shell.dart`'s private `_AppShellState` (issue #209's
/// Today card → "See cycle history" and issue #223's Analysis tab were the
/// two callers named when this seam was tracked -- #314 is the first to use
/// it).
///
/// Split into its own file (rather than living directly in
/// `app_shell.dart`) so `overview_panel.dart` -- which [AppShell] itself
/// already imports to build the Today tab -- can import this file without
/// a mutual import between the two: the same reason `kEstimateDisclaimer`
/// moved out of `overview_panel.dart` into `estimate_copy.dart` (see that
/// file's doc comment).
library;

import 'package:flutter/widgets.dart';

/// The shell's four destinations, in `NavigationBar` order (issue #182's
/// documented assumption: Clue's own B-9/B-29 ordering, no owner sign-off
/// obtained on the exact labels or order).
enum AppTab { today, calendar, insights, more }

/// Exposes the shell's currently-selected tab and a way to switch it, to
/// any descendant of [AppShell]'s body. [maybeOf] returns null when no
/// shell is mounted above the calling context -- `ProfileDetailScreen`'s
/// archived-profile read-only view (which mounts `OverviewPanel` on its
/// own, outside any shell) and any widget test that pumps a tab's content
/// directly rather than the whole shell. Callers must treat a null scope
/// as "there is nowhere to switch to", not as a bug: `OverviewPanel`'s
/// "See cycle history" link hides itself entirely in that case rather than
/// throwing.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.current,
    required this.select,
    required super.child,
  });

  /// The tab currently selected in the shell's `IndexedStack`.
  final AppTab current;

  /// Switches the shell to [tab] -- the same effect as tapping that tab's
  /// `NavigationDestination`, including marking it as ever-built so its
  /// content mounts under the shell's lazy `IndexedStack`. Calls `setState`
  /// on the shell itself, so -- like any other `setState` -- it must be
  /// invoked from an event handler (a tap callback, a stream listener) and
  /// never from inside a `build`/layout pass (a descendant's own `build`,
  /// `didChangeDependencies`, or similar): calling it there throws or is
  /// silently dropped by the framework, since the shell would be asked to
  /// rebuild while already mid-rebuild.
  final void Function(AppTab tab) select;

  static AppShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>();

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      current != oldWidget.current || select != oldWidget.select;
}
