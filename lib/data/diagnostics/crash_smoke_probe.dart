/// Dev-only data-layer crash probe for the #973 crash-report privacy smoke
/// test.
///
/// The trigger that calls this lives in Settings → About and renders only
/// when `AppConfig.crashSmokeEnabled` is true (the `LUNARLOG_CRASH_SMOKE`
/// define *and* a debug build — see `lib/config.dart`), so this file is
/// compiled into debug runs only and tree-shaken out of every store and QA
/// build along with its sole caller.
///
/// It deliberately throws a *neutral* type from a `lib/data` path: the
/// scrubber must recognize a data-layer exception from the stack path
/// alone ([_dataLayerPathMarkers] matching `lunarlog/data/`), which is the
/// route `lib/observability/scrub.dart`'s `_isDataLayerException` takes
/// when `--obfuscate --split-debug-info` has mangled a type name beyond
/// recognition (issue #516). A type-marker probe would only re-prove the
/// already-covered name route.
library;

/// Throws a [StateError] from this `lib/data` file.
///
/// The message is a visible sentinel: if it ever survives into a Sentry
/// payload, the allowlist scrubber has failed and the smoke test failed
/// with it. It names no deny-listed key on purpose — the reduction under
/// test is the stack-path one, not the word scan.
Never throwDataLayerCrashSmoke() {
  throw StateError(
    'crash-report smoke probe (data layer): '
    'this message must be reduced to the type name',
  );
}
