/// [ConsentService] implementation over Supabase (Issue #845): reads the
/// caller's `account_consents` row and writes it through
/// `record_minimum_age_acknowledgement`.
///
/// [fetchMinimumAgeAcknowledgement] never throws (no session, offline, a
/// server error, or a malformed row all read as `null`), the same posture
/// as [SupabaseAccountExportRemoteSource]; a caller deciding whether to
/// re-prompt treats "could not read" exactly like "no record yet".
/// [recordMinimumAgeAcknowledgement] deliberately does throw on a real
/// failure, so its caller can decide how best-effort to be.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/consent/consent_service.dart';

class SupabaseConsentService implements ConsentService {
  const SupabaseConsentService({required this.client});

  final SupabaseClient client;

  @override
  Future<ConsentRecord?> fetchMinimumAgeAcknowledgement() async {
    if (client.auth.currentUser == null) return null;
    try {
      final row = await client
          .from('account_consents')
          .select(
            'consent_via, acknowledged_at, app_version, policy_version',
          )
          .maybeSingle();
      if (row == null) return null;
      return ConsentRecord.fromJson(row.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> recordMinimumAgeAcknowledgement({
    required String consentVia,
    required String appVersion,
    required String policyVersion,
  }) async {
    if (client.auth.currentUser == null) return;
    await client.rpc<void>(
      'record_minimum_age_acknowledgement',
      params: {
        'p_consent_via': consentVia,
        'p_app_version': appVersion,
        'p_policy_version': policyVersion,
      },
    );
  }
}
