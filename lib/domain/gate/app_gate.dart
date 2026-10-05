/// Domain-level credential gate (U7, R7): the single seam through which
/// the app asks "may data be shown?".
///
/// The implementation lives under `lib/startup/gate/`:
/// `local_auth_gate.dart` (mobile/desktop via local_auth) — device
/// credential, biometric with passcode fallback.
///
/// The gate is *advisory to nothing*: the shell (`lib/app_lifecycle.dart`)
/// refuses to render profile data — and on gated platforms refuses to open
/// the database at all — until [requestAccess] returns true (AE4).
library;

abstract interface class AppGate {
  /// Whether this gate actually blocks. True for the local_auth gate.
  bool get requiresUnlock;

  /// Whether the device has any credential enrolled at all (biometric or
  /// passcode) — the same availability check [requestAccess] itself
  /// consults before presenting a prompt. The gate controller (issue #534)
  /// calls this *before* [requestAccess] so it can tell "the operator
  /// declined/failed the prompt" apart from "there was never a prompt to
  /// decline because nothing is enrolled", without opening a system-UI
  /// window for a prompt that will never appear.
  Future<bool> canAuthenticate();

  /// Presents the device-credential prompt (biometric + passcode fallback).
  /// Returns true only when the operator presented a valid credential;
  /// false for every decline, cancellation, or unavailable authenticator —
  /// fail closed.
  Future<bool> requestAccess();
}
