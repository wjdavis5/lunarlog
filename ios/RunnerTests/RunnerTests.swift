import Flutter
import HealthKit
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  /// Issue #916: Verifies that every symptom type identifier accepted across
  /// the platform channel resolves to a valid, non-nil HKCategoryType in Apple HealthKit.
  func testSymptomCategoryTypeIdentifiersResolve() {
    let expectedIdentifiers: [HKCategoryTypeIdentifier] = [
      .abdominalCramps,
      .headache,
      .lowerBackPain,
      .breastPain,
      .bloating,
      .acne,
      .nausea,
      .fatigue,
      .dizziness,
      .moodChanges,
      .sleepChanges,
      .appetiteChanges,
    ]

    for identifier in expectedIdentifiers {
      let categoryType = HKObjectType.categoryType(forIdentifier: identifier)
      XCTAssertNotNil(categoryType, "Expected non-nil HKCategoryType for \(identifier)")
    }

    // Verify all keys in symptomCategoryTypeIdentifiers resolve to valid HKCategoryTypes
    for (wireName, identifier) in HealthKitChannelHandler.symptomCategoryTypeIdentifiers {
      let categoryType = HKObjectType.categoryType(forIdentifier: identifier)
      XCTAssertNotNil(categoryType, "Expected non-nil HKCategoryType for wire '\(wireName)' (\(identifier))")
    }
  }

  /// Issue #917: Verifies that severity raw values match Apple's HKCategoryValueSeverity
  /// definition (HKCategoryValues.h:209-215).
  func testSymptomSeverityValuesMatchAppleSDK() {
    XCTAssertEqual(HKCategoryValueSeverity.unspecified.rawValue, 0)
    XCTAssertEqual(HKCategoryValueSeverity.notPresent.rawValue, 1)
    XCTAssertEqual(HKCategoryValueSeverity.mild.rawValue, 2)
    XCTAssertEqual(HKCategoryValueSeverity.moderate.rawValue, 3)
    XCTAssertEqual(HKCategoryValueSeverity.severe.rawValue, 4)

    XCTAssertEqual(HealthKitChannelHandler.severity(forWire: "unspecified")?.rawValue, 0)
    XCTAssertEqual(HealthKitChannelHandler.severity(forWire: "mild")?.rawValue, 2)
    XCTAssertEqual(HealthKitChannelHandler.severity(forWire: "moderate")?.rawValue, 3)
    XCTAssertEqual(HealthKitChannelHandler.severity(forWire: "severe")?.rawValue, 4)
    XCTAssertNil(HealthKitChannelHandler.severity(forWire: "notPresent"))
    XCTAssertNil(HealthKitChannelHandler.severity(forWire: "unknown"))
  }
}
