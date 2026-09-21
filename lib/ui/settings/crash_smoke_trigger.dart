/// The dev-only crash-report smoke trigger (#973): two Settings → About
/// tiles that each raise an error on purpose so the owner can observe the
/// scrubbed payload in Sentry as part of #19's privacy smoke test.
///
/// Rendered only when `AppConfig.crashSmokeEnabled` is true
/// (`LUNARLOG_CRASH_SMOKE=true` *and* `kDebugMode`); see `lib/config.dart`
/// for why that folds to `false` and tree-shakes the whole surface out of
/// every store build. `AboutSection` injects the flag so widget tests
/// exercise both values in one default-off run.
///
/// Copy is named consts, not inline `Text('...')` literals — the same
/// posture `qa_build_banner.dart` records for QA copy: this is
/// operator-facing English by design and never ships, so the
/// `hardcoded_ui_strings_test.dart` scanner (which flags first-positional
/// `Text('...')` literals) sees nothing to localize or allowlist.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/observability/crash_smoke.dart';

/// Title of the data-layer smoke tile.
const String kCrashSmokeDataTitle = 'Throw data-layer test error';

/// Subtitle of the data-layer smoke tile: names what it does and what the
/// smoke test checks.
const String kCrashSmokeDataSubtitle =
    'Reports a lib/data error to Sentry. The smoke test checks it is '
    'reduced to its type name.';

/// Title of the UI-layer smoke tile.
const String kCrashSmokeUiTitle = 'Throw UI test error';

/// Subtitle of the UI-layer smoke tile.
const String kCrashSmokeUiSubtitle =
    'Reports a lib/ui error to Sentry. The smoke test checks only the '
    'allowlisted fields survive.';

/// The UI-layer probe: throws a [FlutterError] — the one exception type
/// `scrub.dart` keeps verbatim — from this `lib/ui` path. `captureUiCrashSmoke`
/// passes it in as a probe so the reported stack trace points into `lib/ui`
/// without `lib/observability` importing this layer.
Never throwUiCrashSmoke() {
  throw FlutterError('crash-report smoke probe (UI layer)');
}

/// The two dev-only trigger tiles (one tap each: data layer, UI layer).
class CrashSmokeTiles extends StatelessWidget {
  const CrashSmokeTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('crash-smoke-data-tile'),
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text(kCrashSmokeDataTitle),
          subtitle: const Text(kCrashSmokeDataSubtitle),
          onTap: () => captureDataLayerCrashSmoke(),
        ),
        ListTile(
          key: const ValueKey('crash-smoke-ui-tile'),
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text(kCrashSmokeUiTitle),
          subtitle: const Text(kCrashSmokeUiSubtitle),
          onTap: () => captureUiCrashSmoke(probe: throwUiCrashSmoke),
        ),
      ],
    );
  }
}
