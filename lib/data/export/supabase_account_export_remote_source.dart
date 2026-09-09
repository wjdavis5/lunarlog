/// [AccountExportRemoteSource] over `SupabaseClient` (Issue #248): calls
/// the `export_account_data()` RPC and hands back its jsonb document.
///
/// Never throws: [fetchServerExport] returns `null` when there is no
/// signed-in session at all (no point attempting a call the RPC's own
/// `authenticated`-only grant would refuse), and swallows any failure the
/// call itself raises (offline, a server error, a malformed response) into
/// the same `null` - the domain-level merge step
/// (`buildMergedAccountExport` in `lib/domain/export/account_export.dart`)
/// treats every one of those cases identically: fall back to the
/// local-only document.
library;

import 'package:lunarlog/domain/export/account_export_remote_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAccountExportRemoteSource implements AccountExportRemoteSource {
  const SupabaseAccountExportRemoteSource({required this.client});

  final SupabaseClient client;

  @override
  Future<Map<String, Object?>?> fetchServerExport() async {
    if (client.auth.currentUser == null) return null;
    try {
      final data = await client.rpc<dynamic>('export_account_data');
      if (data is! Map) return null;
      return data.cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }
}
