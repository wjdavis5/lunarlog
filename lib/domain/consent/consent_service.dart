/// The account-level minimum-age consent record (Issue #845).
///
/// The acknowledgement used to be a single device-local string
/// (`SettingsKeys.minimumAgeAcknowledged`), so a second signed-in device or
/// a reinstall had no record it ever happened. The owner's 2026-09-20
/// decision made it a synced, owner-only account row:
/// `{acknowledged_at, app_version, policy_version}` plus a `consent_via`
/// discriminator, included in `export_account_data()` and
/// `delete_account_data()` and re-prompted when [kMinimumAgePolicyVersion]
/// changes.
///
/// Pure Dart: no Flutter, no Supabase types cross this boundary (the
/// [ConsentService] convention shared with the other `lib/domain` service
/// seams).
library;

/// The current minimum-age policy version. Bump this when the minimum-age
/// statement's substance changes: a signed-in operator whose stored record
/// carries an older version is re-prompted, and a fresh acknowledgement
/// writes the new value. The date form is deliberate — the version is a
/// human-readable policy revision, not a schema/format version.
const String kMinimumAgePolicyVersion = '2026-09-21';

/// The acknowledgement was made by the operator themselves (the 13+
/// statement on the first-run form).
const String kConsentViaSelf13Plus = 'self_13_plus';

/// The acknowledgement was made by a parent/guardian creating a minor's
/// account, where the invite is itself the parental-consent record
/// (Issue #957, not yet wired).
const String kConsentViaParentInvite = 'parent_invite';

/// A stored minimum-age acknowledgement, as read back from the account.
class ConsentRecord {
  const ConsentRecord({
    required this.consentVia,
    required this.acknowledgedAt,
    required this.appVersion,
    required this.policyVersion,
  });

  /// One of [kConsentViaSelf13Plus] / [kConsentViaParentInvite].
  final String consentVia;

  /// When the acknowledgement was made (server-stamped).
  final DateTime acknowledgedAt;

  /// The app version that made the acknowledgement.
  final String appVersion;

  /// The policy version in force when it was made.
  final String policyVersion;

  /// Parses one row of the server's `account_consents` projection, or
  /// `null` when a required field is missing/unparseable (a malformed row
  /// must never crash the caller; it reads as "no usable record").
  static ConsentRecord? fromJson(Map<String, Object?> json) {
    final consentVia = json['consent_via'];
    final appVersion = json['app_version'];
    final policyVersion = json['policy_version'];
    final acknowledgedAtRaw = json['acknowledged_at'];
    final acknowledgedAt = acknowledgedAtRaw is String
        ? DateTime.tryParse(acknowledgedAtRaw)
        : null;
    if (consentVia is! String ||
        appVersion is! String ||
        policyVersion is! String ||
        acknowledgedAt == null) {
      return null;
    }
    return ConsentRecord(
      consentVia: consentVia,
      acknowledgedAt: acknowledgedAt,
      appVersion: appVersion,
      policyVersion: policyVersion,
    );
  }
}

/// The consent-record seam over the account (Issue #845). The concrete
/// implementation calls the `record_minimum_age_acknowledgement` RPC and
/// reads `account_consents`; a fake stands in for tests. Both methods
/// assume the caller has already established that it should talk to the
/// server at all (a signed-in session); the implementation re-checks the
/// session and turns "no session" into a no-op/`null` rather than an error.
abstract interface class ConsentService {
  /// The caller's stored acknowledgement, or `null` when none exists yet
  /// (or the call failed). Never throws.
  Future<ConsentRecord?> fetchMinimumAgeAcknowledgement();

  /// Upserts the caller's acknowledgement. Throws on a real failure so a
  /// caller can decide whether to retry; the local boolean remains the
  /// offline cache either way.
  Future<void> recordMinimumAgeAcknowledgement({
    required String consentVia,
    required String appVersion,
    required String policyVersion,
  });
}
