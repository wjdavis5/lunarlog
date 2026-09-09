/// Seam for the server-side half of account export (Issue #248). The
/// concrete implementation (`SupabaseAccountExportRemoteSource` in
/// `lib/data/export/`) calls `public.export_account_data()` and hands back
/// its jsonb document; a fake stands in for tests. Pure Dart: no Flutter,
/// no Supabase types cross this boundary, exactly like
/// [FeedbackService][feedback_service_link] and
/// [SharingService][sharing_service_link] beside it.
///
/// [fetchServerExport] never throws — every failure the concrete
/// implementation can hit (no session, no network, a server error) is
/// swallowed and reported as `null`, because export must never fail
/// outright just because its network half didn't work: the merge step
/// (see `mergeAccountExport`/`buildMergedAccountExport` in
/// `account_export.dart`) treats `null` exactly like "no remote source at
/// all" and falls back to the local-only document with
/// `serverIncluded: false`.
///
/// [feedback_service_link]: ../feedback/feedback_service.dart
/// [sharing_service_link]: ../sharing/sharing_service.dart
library;

/// Contract for fetching the server's own account-export document.
abstract interface class AccountExportRemoteSource {
  /// Calls `public.export_account_data()` and returns its decoded jsonb
  /// document, or `null` when the caller is signed out, offline, or the
  /// call otherwise failed. Never throws.
  Future<Map<String, Object?>?> fetchServerExport();
}
