/// Issue #619, LLA-021: pins the canonical Apple SDK raw-value table this
/// repo has no automated way to check `ios/Runner/AppDelegate.swift`'s
/// `MenstrualFlowRawValue` enum against — see
/// `kHealthFlowValueAppleRawValue`'s doc comment in
/// `health_channel_codec.dart` for why (no Swift XCTest target runs in
/// CI). A native reimplementation of the flow enum should be reviewed
/// against these exact literals.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_channel_codec.dart';
import 'package:lunarlog/domain/health/health_platform.dart';

void main() {
  test('every HealthFlowValue has exactly one canonical Apple raw value',
      () {
    expect(
      kHealthFlowValueAppleRawValue.keys.toSet(),
      HealthFlowValue.values.toSet(),
    );
  });

  test(
      'the canonical values match HKCategoryValueVaginalBleeding / '
      'HKCategoryValueMenstrualFlow, independently verified against the '
      'Apple SDK rather than assumed from memory (see the introducing '
      "PR's description for the exact source)", () {
    expect(kHealthFlowValueAppleRawValue[HealthFlowValue.unspecified], 1);
    expect(kHealthFlowValueAppleRawValue[HealthFlowValue.light], 2);
    expect(kHealthFlowValueAppleRawValue[HealthFlowValue.medium], 3);
    expect(kHealthFlowValueAppleRawValue[HealthFlowValue.heavy], 4);
  });

  test(
      'every raw value is unique (no two HealthFlowValues collapse to the '
      'same native sample) and none is 0 — HKCategoryValue.notApplicable, '
      "a different \"no intensity\" concept entirely, is LLA-021's root "
      'cause when mistaken for this enum\'s unspecified', () {
    final values = kHealthFlowValueAppleRawValue.values.toList();
    expect(values.toSet().length, values.length);
    expect(values, isNot(contains(0)));
  });
}
