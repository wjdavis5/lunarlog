/// Web half of the conditional import in `web_url_cleaner.dart`: rewrites
/// the current browser history entry so the spent auth `code` (or the
/// provider's `error` parameters) no longer appear in the address bar.
///
/// `replaceState` — not `pushState` — so no extra history entry is added and
/// the browser Back button keeps working. Pure web-only code; native never
/// compiles this file (see the conditional import).
library;

import 'package:web/web.dart' as web;

/// Replaces the current history entry's URL without navigating. See
/// `web_url_cleaner.dart`.
void replaceBrowserUrl(Uri uri) {
  web.window.history.replaceState(null, '', uri.toString());
}
