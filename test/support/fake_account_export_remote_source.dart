/// [AccountExportRemoteSource] test double (Issue #248): returns a canned
/// result (or null) and records how many times it was called, so tests can
/// assert the merge step's behavior without touching Supabase.
library;

import 'package:lunarlog/domain/export/account_export_remote_source.dart';

class FakeAccountExportRemoteSource implements AccountExportRemoteSource {
  FakeAccountExportRemoteSource({this.result});

  /// What [fetchServerExport] resolves to on every call. Null (the
  /// default) mirrors "signed out / offline / failed".
  Map<String, Object?>? result;

  int callCount = 0;

  @override
  Future<Map<String, Object?>?> fetchServerExport() async {
    callCount++;
    return result;
  }
}
