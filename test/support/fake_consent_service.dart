/// Hand-written [ConsentService] fake (Issue #845): a configurable server
/// read plus a call recorder, so widget tests never touch a Supabase client.
library;

import 'package:lunarlog/domain/consent/consent_service.dart';

class FakeConsentService implements ConsentService {
  FakeConsentService({this.remote});

  /// The row [fetchMinimumAgeAcknowledgement] returns, or null for "none".
  ConsentRecord? remote;

  /// When true, [fetchMinimumAgeAcknowledgement] throws (despite the
  /// interface's never-throws contract) so a caller's defensive handling can
  /// be exercised.
  bool throwOnFetch = false;

  /// Every [recordMinimumAgeAcknowledgement] call, in order.
  final recordCalls = <(
    String consentVia,
    String appVersion,
    String policyVersion,
  )>[];

  @override
  Future<ConsentRecord?> fetchMinimumAgeAcknowledgement() async {
    if (throwOnFetch) throw StateError('simulated consent fetch failure');
    return remote;
  }

  @override
  Future<void> recordMinimumAgeAcknowledgement({
    required String consentVia,
    required String appVersion,
    required String policyVersion,
  }) async {
    recordCalls.add((consentVia, appVersion, policyVersion));
  }
}
