/// Native half of the conditional import in `web_url_cleaner.dart`: a
/// deliberate no-op. A native build has no browser address bar to rewrite,
/// and [SupabaseAuthService] only ever calls the cleaner when it holds a web
/// initial URI — which is null on native — so this is belt and suspenders.
library;

/// Does nothing. See `web_url_cleaner.dart`.
void replaceBrowserUrl(Uri uri) {}
