/// [PinCredentialService] over `flutter_secure_storage` (issue #271; KTD7,
/// R5 — mirrors `lib/data/auth/secure_local_storage.dart`'s Keychain/
/// Keystore options exactly, since both hold device-bound secrets that must
/// never sync or back up).
///
/// Storage shape: two keys, both JSON, both device-local only —
/// * `lunarlog.pin.credential`: `{salt, hash, iterations}` (base64 salt and
///   hash) — a PBKDF2-HMAC-SHA256 digest of the PIN (`pbkdf2.dart`), never
///   the PIN itself (D-2). The Drift database — and therefore the sync
///   engine — never sees any of this: `PinCredentialStore` is constructed
///   independently of the repositories that read/write `day_entries`, and
///   nothing in `lib/data/sync/` reads secure storage at all.
/// * `lunarlog.pin.lockout`: `{failCount, lockedUntil}` — the escalating
///   backoff state ([kPinLockoutSchedule]).
///
/// iOS: `first_unlock_this_device`, non-synchronizable (no iCloud Keychain)
/// — a PIN set on one device never appears, even hashed, on another.
/// Android: the package default (AES-GCM under a Keystore-wrapped key);
/// `allowBackup="false"` in the manifest already keeps it out of backups.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lunarlog/data/gate/pbkdf2.dart';
import 'package:lunarlog/domain/gate/pin_credential_service.dart';

/// Wrong guesses allowed before the first lockout tier begins.
const int kPinFreeAttempts = 3;

/// Escalating lockout duration per tier beyond [kPinFreeAttempts] — mirrors
/// the shape of iOS's own passcode-lockout escalation. The schedule repeats
/// its last (longest) entry for every attempt beyond it, so lockout never
/// shortens as failures keep accumulating.
const List<Duration> kPinLockoutSchedule = [
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(minutes: 30),
];

const int _saltLengthBytes = 16;

class PinCredentialStore implements PinCredentialService {
  PinCredentialStore({
    FlutterSecureStorage? storage,
    this._now = DateTime.now,
    Random? random,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  final Random _random;

  static const String _credentialKey = 'lunarlog.pin.credential';
  static const String _lockoutKey = 'lunarlog.pin.lockout';

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );
  static const AndroidOptions _androidOptions = AndroidOptions();

  @override
  Future<bool> isPinSet() => _storage.containsKey(
        key: _credentialKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );

  @override
  Future<void> setPin(String pin) async {
    final salt = Uint8List.fromList(
        List<int>.generate(_saltLengthBytes, (_) => _random.nextInt(256)));
    final hash = pbkdf2HmacSha256(password: utf8.encode(pin), salt: salt);
    final payload = jsonEncode({
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
      'iterations': kPbkdf2DefaultIterations,
    });
    await _write(_credentialKey, payload);
    await _clearLockout();
  }

  @override
  Future<void> clearPin() async {
    await _storage.delete(
      key: _credentialKey,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
      mOptions: _iosOptions,
    );
    await _clearLockout();
  }

  @override
  Future<PinVerification> verifyPin(String pin) async {
    final lockout = await _readLockout();
    if (lockout.lockedUntil != null &&
        lockout.lockedUntil!.isAfter(_now())) {
      // A guess made while locked out is never checked against the stored
      // hash, and never extends or resets the existing lockout.
      return PinVerification(
        outcome: PinCheckOutcome.lockedOut,
        lockedUntil: lockout.lockedUntil,
        remainingFreeAttempts: 0,
      );
    }

    final raw = await _read(_credentialKey);
    if (raw == null) {
      // No PIN set — a caller error (the UI should never reach this screen
      // without one), but fail closed rather than treat it as a match.
      return const PinVerification(
        outcome: PinCheckOutcome.incorrect,
        remainingFreeAttempts: 0,
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final salt = base64Decode(decoded['salt'] as String);
    final storedHash = base64Decode(decoded['hash'] as String);
    final iterations = decoded['iterations'] as int;
    final candidate = pbkdf2HmacSha256(
      password: utf8.encode(pin),
      salt: salt,
      iterations: iterations,
    );
    if (constantTimeEquals(candidate, storedHash)) {
      await _clearLockout();
      return const PinVerification(
        outcome: PinCheckOutcome.correct,
        remainingFreeAttempts: kPinFreeAttempts,
      );
    }
    return _recordFailure(lockout.failCount);
  }

  @override
  Future<PinLockoutState> lockoutState() async {
    final lockout = await _readLockout();
    if (lockout.lockedUntil != null && !lockout.lockedUntil!.isAfter(_now())) {
      return const PinLockoutState();
    }
    return PinLockoutState(lockedUntil: lockout.lockedUntil);
  }

  /// Bumps the fail count, computes the next lockout tier (if any beyond
  /// [kPinFreeAttempts]), and persists both.
  Future<PinVerification> _recordFailure(int previousFailCount) async {
    final failCount = previousFailCount + 1;
    if (failCount <= kPinFreeAttempts) {
      await _writeLockout(failCount: failCount, lockedUntil: null);
      return PinVerification(
        outcome: PinCheckOutcome.incorrect,
        remainingFreeAttempts: kPinFreeAttempts - failCount,
      );
    }
    final tier = (failCount - kPinFreeAttempts - 1)
        .clamp(0, kPinLockoutSchedule.length - 1);
    final lockedUntil = _now().add(kPinLockoutSchedule[tier]);
    await _writeLockout(failCount: failCount, lockedUntil: lockedUntil);
    return PinVerification(
      outcome: PinCheckOutcome.lockedOut,
      lockedUntil: lockedUntil,
      remainingFreeAttempts: 0,
    );
  }

  Future<({int failCount, DateTime? lockedUntil})> _readLockout() async {
    final raw = await _read(_lockoutKey);
    if (raw == null) return (failCount: 0, lockedUntil: null);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final lockedUntilRaw = decoded['lockedUntil'] as String?;
    return (
      failCount: decoded['failCount'] as int? ?? 0,
      lockedUntil: lockedUntilRaw == null ? null : DateTime.parse(lockedUntilRaw),
    );
  }

  Future<void> _writeLockout({
    required int failCount,
    required DateTime? lockedUntil,
  }) =>
      _write(
        _lockoutKey,
        jsonEncode({
          'failCount': failCount,
          'lockedUntil': lockedUntil?.toIso8601String(),
        }),
      );

  Future<void> _clearLockout() => _storage.delete(
        key: _lockoutKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );

  Future<String?> _read(String key) => _storage.read(
        key: key,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );

  Future<void> _write(String key, String value) => _storage.write(
        key: key,
        value: value,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );
}
