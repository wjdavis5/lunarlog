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

  /// Issue #992: Pins the paging-cursor codec on the Swift side. Dart treats
  /// the cursor as opaque and only compares cursors for progress, but the
  /// bytes that cross the channel must round-trip and malformed input must
  /// decode to "start over" rather than throw or silently mislead.
  func testImportCursorDataRoundTripsAndRejectsMalformedInput() {
    let data = Data([0x01, 0x02, 0xFE, 0xFF])
    let encoded = HealthKitChannelHandler.encodeCursorData(data)
    XCTAssertEqual(HealthKitChannelHandler.decodeCursorData(encoded), data)

    // Absent/empty/malformed cursors decode to nil, never a crash.
    XCTAssertNil(HealthKitChannelHandler.decodeCursorData(nil))
    XCTAssertNil(HealthKitChannelHandler.decodeCursorData(""))
    XCTAssertNil(HealthKitChannelHandler.decodeCursorData("***not-base64***"))
  }

  /// Issue #992: An anchor that is not from this build's query decodes to
  /// nil (a fresh start) rather than throwing. `HKQueryAnchor` has no public
  /// initializer, so the round-trip itself is covered by
  /// `testImportCursorDataRoundTripsAndRejectsMalformedInput`.
  func testImportCursorAnchorRejectsNonAnchorInput() {
    XCTAssertNil(HealthKitChannelHandler.decodeAnchor(nil))
    XCTAssertNil(HealthKitChannelHandler.decodeAnchor(""))
    XCTAssertNil(
      HealthKitChannelHandler.decodeAnchor(
        HealthKitChannelHandler.encodeCursorData(Data([0x00, 0x01, 0x02]))))
  }

  /// Issue #920: Verifies that BBT samples are built as instant samples (startDate == endDate)
  /// rather than whole-day intervals ending at 23:59:59.
  func testBasalBodyTemperatureSampleIsInstant() {
    let instantMs: Int64 = 1780401600000 // 2026-06-02 11:00:00 UTC (07:00 EDT)
    let sample = HealthKitChannelHandler.buildBasalBodyTemperatureSample(
      celsius: 36.7,
      startMs: instantMs,
      endMs: instantMs,
      recordId: "bbt-record-1",
      recordVersionMs: 123456
    )

    XCTAssertEqual(sample.startDate, sample.endDate, "BBT sample must be an instant (startDate == endDate)")
    XCTAssertEqual(sample.startDate, Date(timeIntervalSince1970: Double(instantMs) / 1000.0))
    XCTAssertEqual(sample.quantity.doubleValue(for: .degreeCelsius()), 36.7, accuracy: 0.0001)
    XCTAssertEqual(sample.metadata?[HKMetadataKeyExternalUUID] as? String, "bbt-record-1")
    XCTAssertEqual(sample.metadata?[HKMetadataKeySyncIdentifier] as? String, "bbt-record-1")
    XCTAssertEqual(sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber, 123456)
  }
}
