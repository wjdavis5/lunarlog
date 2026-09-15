/// [GateController]'s in-app PIN layer (issue #271 D-6): the second-layer
/// step after a granted device credential, the standalone path for a device
/// with none enrolled at all, and the unaffected-path guarantee for a
/// controller with no PIN configured. [PinCredentialStore]'s own hashing/
/// lockout logic is covered separately in `test/data/gate/`; this suite
/// fakes [PinCredentialService] entirely so it only exercises
/// [GateController]'s own state machine.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/gate_controller.dart';

import 'gate_test.dart' show FakeGate, FakeInactivityTimers;

class FakePinCredentialService implements PinCredentialService {
  bool pinSet = false;
  String? storedPin;
  PinVerification? nextVerification;
  PinLockoutState lockout = const PinLockoutState();

  final verifyCalls = <String>[];
  int setPinCalls = 0;
  int clearPinCalls = 0;

  @override
  Future<bool> isPinSet() async => pinSet;

  @override
  Future<void> setPin(String pin) async {
    setPinCalls++;
    storedPin = pin;
    pinSet = true;
  }

  @override
  Future<void> clearPin() async {
    clearPinCalls++;
    storedPin = null;
    pinSet = false;
  }

  @override
  Future<PinLockoutState> lockoutState() async => lockout;

  @override
  Future<PinVerification> verifyPin(String pin) async {
    verifyCalls.add(pin);
    final forced = nextVerification;
    if (forced != null) return forced;
    return PinVerification(
      outcome: pin == storedPin
          ? PinCheckOutcome.correct
          : PinCheckOutcome.incorrect,
      remainingFreeAttempts: 2,
    );
  }
}

void main() {
  // GateController's constructor reads WidgetsBinding.instance
  // (addObserver); every test here constructs one directly with plain
  // `test()`, not `testWidgets()`, so the binding needs an explicit init.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GateController + PinCredentialService (#271)', () {
    test('no PIN service configured: unlock behaves exactly as before #271',
        () async {
      final gate = FakeGate();
      final controller = GateController(gate: gate);
      addTearDown(controller.dispose);

      await controller.unlock();

      expect(controller.locked, isFalse);
      expect(controller.pinRequired, isFalse);
      expect(controller.pinAvailable, isFalse);
    });

    test('PIN service configured but no PIN set: unlock behaves as before',
        () async {
      final gate = FakeGate();
      final pin = FakePinCredentialService();
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);

      await controller.unlock();

      expect(controller.locked, isFalse);
      expect(controller.pinRequired, isFalse);
    });

    test(
        'PIN set + device credential granted: stays locked and requires the '
        'PIN as a second layer', () async {
      final gate = FakeGate();
      final pin = FakePinCredentialService()
        ..pinSet = true
        ..storedPin = '1234';
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);

      await controller.unlock();

      expect(controller.locked, isTrue,
          reason: 'a granted device credential alone must not open the app '
              'when a PIN is also required');
      expect(controller.pinRequired, isTrue);
      expect(controller.denialReason, GateDenialReason.none);
    });

    test('a correct PIN completes the unlock', () async {
      final gate = FakeGate();
      final pin = FakePinCredentialService()
        ..pinSet = true
        ..storedPin = '1234';
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);
      await controller.unlock();

      final result = await controller.submitPin('1234');

      expect(result.outcome, PinCheckOutcome.correct);
      expect(controller.locked, isFalse);
      expect(controller.pinRequired, isFalse);
    });

    test('a wrong PIN leaves the gate locked and pinRequired true', () async {
      final gate = FakeGate();
      final pin = FakePinCredentialService()
        ..pinSet = true
        ..storedPin = '1234';
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);
      await controller.unlock();

      final result = await controller.submitPin('0000');

      expect(result.outcome, PinCheckOutcome.incorrect);
      expect(controller.locked, isTrue);
      expect(controller.pinRequired, isTrue);
    });

    test(
        'no device credential enrolled + PIN set: the PIN stands alone '
        'instead of the noCredentialEnrolled dead end', () async {
      final gate = FakeGate(canAuthenticateNext: false);
      final pin = FakePinCredentialService()
        ..pinSet = true
        ..storedPin = '1234';
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);

      await controller.unlock();

      expect(controller.pinRequired, isTrue);
      expect(controller.denialReason, GateDenialReason.none,
          reason: 'the no-credential dead end must not fire when a PIN can '
              'stand alone');
      expect(controller.locked, isTrue);

      final result = await controller.submitPin('1234');
      expect(result.outcome, PinCheckOutcome.correct);
      expect(controller.locked, isFalse);
    });

    test(
        'no device credential enrolled + no PIN set: unaffected — the '
        'pre-#271 dead end still fires', () async {
      final gate = FakeGate(canAuthenticateNext: false);
      final pin = FakePinCredentialService();
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);

      await controller.unlock();

      expect(controller.pinRequired, isFalse);
      expect(controller.denialReason, GateDenialReason.noCredentialEnrolled);
    });

    test('lock() discards a pending PIN step', () async {
      final gate = FakeGate();
      final pin = FakePinCredentialService()
        ..pinSet = true
        ..storedPin = '1234';
      final controller = GateController(
        gate: gate,
        pinService: pin,
        inactivityTimerFactory: FakeInactivityTimers().factory,
      );
      addTearDown(controller.dispose);
      await controller.unlock();
      expect(controller.pinRequired, isTrue);

      controller.lock();

      expect(controller.pinRequired, isFalse);
      expect(controller.locked, isTrue);
    });

    test('a locked-out PIN attempt is refused without touching the stored hash',
        () async {
      final gate = FakeGate();
      final pin = FakePinCredentialService()
        ..pinSet = true
        ..storedPin = '1234'
        ..nextVerification = PinVerification(
          outcome: PinCheckOutcome.lockedOut,
          lockedUntil: DateTime.now().add(const Duration(minutes: 1)),
          remainingFreeAttempts: 0,
        );
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);
      await controller.unlock();

      final result = await controller.submitPin('1234');

      expect(result.outcome, PinCheckOutcome.lockedOut);
      expect(controller.locked, isTrue);
    });

    test('settings passthroughs delegate to the configured PinCredentialService',
        () async {
      final gate = FakeGate();
      final pin = FakePinCredentialService();
      final controller = GateController(gate: gate, pinService: pin);
      addTearDown(controller.dispose);

      expect(await controller.isPinSet(), isFalse);
      await controller.setPin('4242');
      expect(pin.setPinCalls, 1);
      expect(await controller.isPinSet(), isTrue);
      await controller.clearPin();
      expect(pin.clearPinCalls, 1);
    });

    test('settings passthroughs throw StateError with no PIN service', () {
      final controller = GateController(gate: FakeGate());
      addTearDown(controller.dispose);

      expect(() => controller.setPin('1234'), throwsStateError);
      expect(() => controller.clearPin(), throwsStateError);
      expect(() => controller.verifyPinForSettings('1234'), throwsStateError);
      expect(() => controller.submitPin('1234'), throwsStateError);
    });
  });
}
