/// Domain service enforcing the device-local binding invariant (Issue
/// #153): at most one profile may ever be "this device's health-store
/// owner" at a time. Backed by [SettingsStore]'s single-valued
/// [SettingsKeys.healthStoreProfileId] key, so "at most one" holds by
/// construction — there is only ever one stored value to read.
///
/// **This class owns the entire health-sync policy decision — see
/// `health_sync_policy.dart`'s library doc for the full write-up.** The
/// pure check both [canBind] and [canWrite] share ([_evaluate], below) is
/// private to this file: no adapter, screen, or test outside
/// `lib/domain/health/` may construct its inputs directly. [canWrite] is
/// the one every future HealthKit/Health Connect write path MUST call
/// before writing anything — it reads the *actually stored* binding
/// itself rather than trusting a caller-supplied value, closing a P0
/// review finding: this file's own [bind] method, and the Settings
/// picker, both used to pass `canSyncProfile(boundProfileId: profile.id)`
/// — the *proposed* id — which neutralised the device-binding check for
/// the one call site that actually persists a binding. [canBind] keeps
/// that "proposed id" shape deliberately (there is nothing stored yet to
/// read at that point), but it is now the *only* entry point allowed to
/// use it.
///
/// [bind] refuses (returns a non-[HealthSyncCheck.allowed] result without
/// persisting anything) whenever [canBind] would deny the proposed
/// binding, so a denied profile can never even be selected in Settings,
/// let alone written to the OS health store later.
///
/// **Design decision — replace, not require-unbind-first** (documented per
/// the issue's "choose and document" ask): [bind] *replaces* any existing
/// binding outright rather than requiring an explicit [unbind] call first.
/// This follows the issue's own Settings UI acceptance criterion directly
/// ("selecting a new profile clears the previous mapping") and is safe
/// because the invariant is structural either way: the setting is
/// single-valued, so there is never a moment with two profiles bound
/// regardless of which flow changes it. Requiring a separate unbind step
/// first would only add friction to what is fundamentally one picker
/// selection, without adding any additional safety.
///
/// Pure Dart (R14/R16); depends only on the [SettingsStore] interface, not
/// any concrete storage — `test/architecture/layering_test.dart` enforces
/// the import discipline, and
/// `test/architecture/health_sync_binding_scope_test.dart` asserts
/// [SettingsKeys.healthStoreProfileId] is read only inside this
/// directory.
library;

import '../models/profile.dart';
import '../repositories/settings_store.dart';
import 'health_sync_policy.dart';

class HealthSyncBinding {
  const HealthSyncBinding(this._settings);

  final SettingsStore _settings;

  /// The bound profile id, or null when none is set (the default: health
  /// sync off for every profile on this device).
  Future<String?> boundProfileId() async {
    final value = await _settings.get(SettingsKeys.healthStoreProfileId);
    return _normalize(value);
  }

  /// Reactive variant of [boundProfileId] — emits the current value and
  /// again on every change.
  Stream<String?> watchBoundProfileId() => _settings
      .watch(SettingsKeys.healthStoreProfileId)
      .map(_normalize);

  static String? _normalize(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  /// Whether binding [profile] as this device's sole health-store profile
  /// would be allowed right now — evaluated against the *proposed*
  /// binding (`profile.id`), since nothing is stored yet at this point, so
  /// only the minor and ownership checks can produce a deny. Used by the
  /// Settings picker to show why an ineligible profile is refused, and by
  /// [bind] itself before persisting anything. [minorBindingAllowed] must
  /// be `AppConfig.healthSyncMinorBindingAllowed` (`lib/config.dart`) —
  /// never a locally invented value; kept as a required parameter here
  /// (rather than read directly) because `lib/domain` stays pure Dart and
  /// cannot import `AppConfig` (R14/R16).
  HealthSyncCheck canBind({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) =>
      _evaluate(
        profile: profile,
        boundProfileId: profile.id,
        signedInUserId: signedInUserId,
        ownerUserId: ownerUserId,
        minorBindingAllowed: minorBindingAllowed,
      );

  /// Whether [profile]'s data may be written to this device's OS health
  /// store right now — the real write guard every platform adapter MUST
  /// call before writing anything, and the only entry point that may ever
  /// gate an actual write. Reads the *actually stored* binding itself
  /// ([SettingsKeys.healthStoreProfileId]) rather than trusting a
  /// caller-supplied value, so a caller cannot neutralise the
  /// device-binding check by passing its own profile id — denying
  /// [HealthSyncCheck.noBinding]/[HealthSyncCheck.profileNotBound]
  /// whenever the stored binding is unset or points elsewhere, no matter
  /// what [profile] the caller asks about. See [canBind]'s doc for
  /// [minorBindingAllowed].
  Future<HealthSyncCheck> canWrite({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) async =>
      _evaluate(
        profile: profile,
        boundProfileId: await boundProfileId(),
        signedInUserId: signedInUserId,
        ownerUserId: ownerUserId,
        minorBindingAllowed: minorBindingAllowed,
      );

  /// The pure decision [canBind] and [canWrite] share. Private to this
  /// file — see the class doc and `health_sync_policy.dart`'s library doc
  /// for why nothing else may call this or construct its inputs directly.
  /// Total — never throws.
  static HealthSyncCheck _evaluate({
    required Profile profile,
    required String? boundProfileId,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) {
    if (boundProfileId == null) return HealthSyncCheck.noBinding;
    if (profile.id != boundProfileId) return HealthSyncCheck.profileNotBound;

    final isOwner = signedInUserId != null &&
        ownerUserId != null &&
        signedInUserId == ownerUserId;

    if (_isMinorNow(profile)) {
      final transferredToOwnAccount =
          profile.transferredAt != null && isOwner;
      if (!minorBindingAllowed || !transferredToOwnAccount) {
        return HealthSyncCheck.minorRequiresOwnershipTransfer;
      }
      return HealthSyncCheck.allowed;
    }

    if (!isOwner) return HealthSyncCheck.notOwner;
    return HealthSyncCheck.allowed;
  }

  /// Whether [profile] counts as a minor for the gate above: either
  /// flagged directly via [Profile.isMinor], or not flagged but under 18
  /// by [Profile.birthYear] — unticking "Minor" in the profile dialog must
  /// never by itself clear this deny. [Profile.birthYear] is a year-only
  /// field (no month/day), so this is a coarse same-calendar-year
  /// comparison against the current year, not an exact birthday check.
  static bool _isMinorNow(Profile profile) {
    if (profile.isMinor) return true;
    final birthYear = profile.birthYear;
    if (birthYear == null) return false;
    return DateTime.now().year - birthYear < 18;
  }

  /// Attempts to bind [profile] as this device's sole health-store
  /// profile. Evaluates [canBind] before writing anything, so a denied
  /// profile is never persisted even transiently — the deny reason is
  /// returned instead and the stored setting is left untouched. On
  /// success, replaces any existing binding (see the class doc above) and
  /// returns [HealthSyncCheck.allowed].
  Future<HealthSyncCheck> bind({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    required bool minorBindingAllowed,
  }) async {
    final decision = canBind(
      profile: profile,
      signedInUserId: signedInUserId,
      ownerUserId: ownerUserId,
      minorBindingAllowed: minorBindingAllowed,
    );
    if (!decision.isAllowed) return decision;
    await _settings.set(SettingsKeys.healthStoreProfileId, profile.id);
    return HealthSyncCheck.allowed;
  }

  /// Clears the binding — health sync goes back to off for every profile
  /// on this device until the operator binds one again.
  Future<void> unbind() =>
      _settings.set(SettingsKeys.healthStoreProfileId, '');
}
