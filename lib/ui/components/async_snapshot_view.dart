/// Shared `snapshot.hasError` → `InlineError` handling (issue #543) for the
/// common `StreamBuilder`/`FutureBuilder` shape used across the main tabs:
/// `snapshot.data == null` means "still loading" (the stream/future never
/// legitimately emits a null value), and a thrown error must not collapse
/// into the same silent spinner. Reach for this instead of re-deriving the
/// three-way loading/error/data branch at each call site — see
/// `lib/ui/README.md`'s inline-error rule for why the error case renders
/// `InlineError` rather than a bespoke message.
///
/// Not every `StreamBuilder` site fits this shape (e.g. `month_calendar.dart`
/// and `cycle_history_section.dart` treat a null stream, an empty result,
/// and "still loading" differently), so those keep their own inline
/// `snapshot.hasError` branch rather than being forced through here.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/tokens.dart';
import 'inline_error.dart';

class AsyncSnapshotView<T> extends StatelessWidget {
  const AsyncSnapshotView({
    super.key,
    required this.snapshot,
    required this.builder,
    this.onRetry,
    this.errorMessage,
    this.loadingBuilder,
  });

  final AsyncSnapshot<T> snapshot;

  /// Rendered once the stream/future has produced a non-null value.
  final Widget Function(BuildContext context, T data) builder;

  /// Null when the surrounding UI already offers its own retry (rare for
  /// this shape — most callers pass a resubscribe callback).
  final VoidCallback? onRetry;

  /// Null renders the arb-backed generic error copy
  /// (`commonSomethingWentWrong`, issue #1004 tranche 5 — the defaulted
  /// English literal this field used to carry).
  final String? errorMessage;

  /// Defaults to a centered spinner; override for a call site that wants a
  /// smaller or differently-placed loading indicator.
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (snapshot.hasError) {
      child = KeyedSubtree(
        key: const ValueKey('async-snapshot-error'),
        child: Center(
          child: InlineError(
            message:
                errorMessage ?? AppLocalizations.of(context).commonSomethingWentWrong,
            onRetry: onRetry,
          ),
        ),
      );
    } else {
      final data = snapshot.data;
      if (data == null) {
        child = KeyedSubtree(
          key: const ValueKey('async-snapshot-loading'),
          child: loadingBuilder?.call(context) ??
              const Center(child: CircularProgressIndicator()),
        );
      } else {
        child = KeyedSubtree(
          key: const ValueKey('async-snapshot-data'),
          child: builder(context, data),
        );
      }
    }
    // Issue #809: loading -> content (and error -> content) now fades at the
    // base duration instead of snapping. This is the highest-leverage site
    // in the change: every screen rendering this view inherits the fade, and
    // the state keys above mean a data update that stays in the same state
    // rebuilds without re-triggering the transition.
    return AnimatedSwitcher(
      duration: LLMotion.resolve(context, LLMotion.base),
      child: child,
    );
  }
}
