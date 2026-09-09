/// Domain service enforcing the device-local binding invariant (Issue
/// #153): at most one profile may ever be "this device's health-store
/// owner" at a time. Backed by [SettingsStore]'s single-valued
/// [SettingsKeys.healthStoreProfileId] key, so "at most one" holds by
/// construction — there is only ever one stored value to read.
///
/// [bind] refuses (returns a non-[HealthSyncCheck.allowed] result without
/// persisting anything) whenever [canSyncProfile] would deny the proposed
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
/// the import discipline.
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

  /// Attempts to bind [profile] as this device's sole health-store
  /// profile. Evaluates [canSyncProfile] against the *proposed* binding
  /// (`boundProfileId: profile.id`) before writing anything, so a denied
  /// profile is never persisted even transiently — the deny reason is
  /// returned instead and the stored setting is left untouched. On
  /// success, replaces any existing binding (see the class doc above) and
  /// returns [HealthSyncCheck.allowed].
  Future<HealthSyncCheck> bind({
    required Profile profile,
    required String? signedInUserId,
    required String? ownerUserId,
    bool minorBindingAllowed = false,
  }) async {
    final decision = canSyncProfile(
      profile: profile,
      boundProfileId: profile.id,
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
