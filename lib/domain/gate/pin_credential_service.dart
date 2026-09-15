/// In-app PIN domain seam (issue #271; KTD-pin). Pure Dart, mirroring
/// [AuthService]'s split: the implementation
/// (`lib/data/gate/pin_credential_store.dart`) hashes and rate-limits over
/// `flutter_secure_storage`; nothing here knows about secure storage, Drift,
/// or Flutter.
///
/// The PIN itself is never stored, logged, or returned by any member here —
/// only a salted, slow hash crosses into storage (D-2 of the issue). See
/// `PinCredentialStore`'s doc comment for the KDF and storage shape.
library;

import 'package:meta/meta.dart';

/// Outcome of [PinCredentialService.verifyPin].
enum PinCheckOutcome {
  /// The PIN matched. Lockout state is cleared.
  correct,

  /// The PIN did not match; [PinVerification.remainingFreeAttempts] says
  /// how many more attempts remain before the next lockout tier.
  incorrect,

  /// Too many recent wrong attempts — [PinVerification.lockedUntil] names
  /// when the next attempt may be made. The candidate PIN is never checked
  /// against the stored hash while locked out (a locked-out guess never
  /// resets or extends anything).
  lockedOut,
}

@immutable
class PinVerification {
  const PinVerification({
    required this.outcome,
    this.lockedUntil,
    required this.remainingFreeAttempts,
  });

  final PinCheckOutcome outcome;

  /// Non-null only for [PinCheckOutcome.lockedOut].
  final DateTime? lockedUntil;

  /// How many more wrong attempts remain before the next lockout tier
  /// begins. Meaningful only for [PinCheckOutcome.incorrect] — zero for
  /// [PinCheckOutcome.lockedOut] and [PinCheckOutcome.correct].
  final int remainingFreeAttempts;
}

/// The PIN entry UI's current lockout state, readable without attempting a
/// verification — e.g. to render a countdown or disable the keypad on
/// screen open after the app was relaunched mid-lockout.
@immutable
class PinLockoutState {
  const PinLockoutState({this.lockedUntil});

  /// Null when no lockout is in effect.
  final DateTime? lockedUntil;

  bool isLockedOutAt(DateTime now) =>
      lockedUntil != null && lockedUntil!.isAfter(now);
}

/// The optional in-app PIN gate (#271 D-6): a second, additive lock layer
/// on top of the device credential, and a standalone lock when the device
/// has none set at all.
///
/// [setPin] and [clearPin] perform no verification of their own — the UI is
/// responsible for having already confirmed the operator's right to change
/// or remove the PIN, either via [verifyPin] (the current PIN) or the
/// device credential (`GateController.reauthenticate`), per the issue's
/// "changing or removing requires the current PIN or device auth"
/// acceptance criterion. Creating a PIN where none exists needs no such
/// check — there is nothing yet to prove ownership of.
abstract interface class PinCredentialService {
  Future<bool> isPinSet();

  /// Checks [pin] against the stored hash, applying and updating the
  /// escalating lockout backoff on a wrong guess (#271 D-6). A guess made
  /// while already locked out is refused without being checked, and does
  /// not extend the existing lockout.
  Future<PinVerification> verifyPin(String pin);

  /// Replaces (or creates) the stored PIN and clears any lockout state.
  Future<void> setPin(String pin);

  /// Removes the PIN entirely and clears any lockout state.
  Future<void> clearPin();

  /// The current lockout state, without attempting a verification.
  Future<PinLockoutState> lockoutState();
}
