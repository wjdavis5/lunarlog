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

  // MARK: - Issue #1610: the stored import anchor and the page shape
  //
  // `HKQueryAnchor` has no public initializer (the #992 tests say the same),
  // so the one shape below that needs a decodable anchor — a stored payload
  // decoding to an incremental first page, and a real page's nextCursor /
  // commitToken round-trip — cannot be constructed here. Everything the
  // decision and the payload assembly do around that gap is.

  private let anchorProfileA = "test-profile-a-1610"
  private let anchorProfileB = "test-profile-b-1610"

  override func tearDownWithError() throws {
    UserDefaults.standard.removeObject(
      forKey: HealthKitChannelHandler.importAnchorKey(anchorProfileA))
    UserDefaults.standard.removeObject(
      forKey: HealthKitChannelHandler.importAnchorKey(anchorProfileB))
    try super.tearDownWithError()
  }

  /// The anchor is stored per bound profile: two profiles never share a
  /// position, and dropping one leaves the other alone.
  func testImportAnchorIsStoredAndDroppedPerProfile() {
    let keyA = HealthKitChannelHandler.importAnchorKey(anchorProfileA)
    let keyB = HealthKitChannelHandler.importAnchorKey(anchorProfileB)
    XCTAssertNotEqual(keyA, keyB)

    HealthKitChannelHandler.storeImportAnchor(anchorProfileA, "payload-a")
    HealthKitChannelHandler.storeImportAnchor(anchorProfileB, "payload-b")
    XCTAssertEqual(HealthKitChannelHandler.storedImportAnchor(anchorProfileA), "payload-a")
    XCTAssertEqual(HealthKitChannelHandler.storedImportAnchor(anchorProfileB), "payload-b")

    HealthKitChannelHandler.dropStoredImportAnchor(anchorProfileA)
    XCTAssertNil(HealthKitChannelHandler.storedImportAnchor(anchorProfileA))
    XCTAssertEqual(HealthKitChannelHandler.storedImportAnchor(anchorProfileB), "payload-b")
  }

  /// A first page with nothing stored reads everything: not an incremental
  /// page, and it stores nothing.
  func testStartingPageWithNoStoredAnchorReadsEverything() {
    let page = HealthKitChannelHandler.startingPage(
      profileId: anchorProfileA, cursor: nil, wholeHistory: false)
    XCTAssertNil(page.anchor)
    XCTAssertFalse(page.incremental)
    XCTAssertNil(HealthKitChannelHandler.storedImportAnchor(anchorProfileA))
  }

  /// `wholeHistory: true` on a first page drops the stored anchor — even a
  /// corrupt one — and reads everything. This is what makes a pass that
  /// ends early be followed by another whole read: the position stays gone
  /// until a commit re-establishes it.
  func testStartingPageWholeHistoryDropsTheStoredAnchor() {
    HealthKitChannelHandler.storeImportAnchor(anchorProfileA, "garbage")
    let page = HealthKitChannelHandler.startingPage(
      profileId: anchorProfileA, cursor: nil, wholeHistory: true)
    XCTAssertNil(page.anchor)
    XCTAssertFalse(page.incremental)
    XCTAssertNil(
      HealthKitChannelHandler.storedImportAnchor(anchorProfileA),
      "the stored position must be gone, not merely ignored")
  }

  /// A stored payload this build cannot read is no position: the read
  /// starts over as a full read, and the wreck is dropped so the next
  /// commit writes a fresh one.
  func testStartingPageCorruptStoredAnchorReadsEverythingAndIsDropped() {
    HealthKitChannelHandler.storeImportAnchor(anchorProfileA, "garbage")
    let page = HealthKitChannelHandler.startingPage(
      profileId: anchorProfileA, cursor: nil, wholeHistory: false)
    XCTAssertNil(page.anchor)
    XCTAssertFalse(page.incremental)
    XCTAssertNil(HealthKitChannelHandler.storedImportAnchor(anchorProfileA))
  }

  /// A later page whose cursor this build cannot read starts over as a full
  /// read too — and touches no stored anchor on the way.
  func testStartingPageMalformedCursorReadsEverything() {
    HealthKitChannelHandler.storeImportAnchor(anchorProfileA, "stored-but-unread")
    let page = HealthKitChannelHandler.startingPage(
      profileId: anchorProfileA, cursor: "not-a-payload", wholeHistory: false)
    XCTAssertNil(page.anchor)
    XCTAssertFalse(page.incremental)
    XCTAssertEqual(
      HealthKitChannelHandler.storedImportAnchor(anchorProfileA),
      "stored-but-unread",
      "the cursor branch decides only the page; it must not touch storage")
  }

  /// A nil anchor serializes to nothing: no cursor is ever fabricated
  /// without an anchor, so a page HealthKit gave no anchor for advances no
  /// position.
  func testAnchorPayloadOfNilAnchorIsNil() {
    XCTAssertNil(HealthKitChannelHandler.encodeAnchorPayload(nil, incremental: true))
    XCTAssertNil(HealthKitChannelHandler.encodeAnchorPayload(nil, incremental: false))
  }

  /// Every unreadable payload decodes to nil — "no position" — never a
  /// crash: absent, not base64, base64 of non-JSON, JSON without an anchor,
  /// and JSON whose archived anchor is not an `HKQueryAnchor`.
  func testAnchorPayloadRejectsMalformedAndForeignPayloads() {
    XCTAssertNil(HealthKitChannelHandler.decodeAnchorPayload(nil))
    XCTAssertNil(HealthKitChannelHandler.decodeAnchorPayload(""))
    XCTAssertNil(HealthKitChannelHandler.decodeAnchorPayload("***not-base64***"))

    func payloadJson(_ json: String) -> String {
      HealthKitChannelHandler.encodeCursorData(Data(json.utf8))
    }
    XCTAssertNil(HealthKitChannelHandler.decodeAnchorPayload(payloadJson("not json")))
    XCTAssertNil(
      HealthKitChannelHandler.decodeAnchorPayload(payloadJson(#"{"incremental": true}"#)))
    XCTAssertNil(
      HealthKitChannelHandler.decodeAnchorPayload(
        payloadJson(#"{"anchor": "***not-base64***", "incremental": true}"#)))
    // Valid base64 of a non-anchor archive: the unarchive gate.
    let notAnAnchor = HealthKitChannelHandler.encodeCursorData(Data([0x00, 0x01, 0x02]))
    XCTAssertNil(
      HealthKitChannelHandler.decodeAnchorPayload(
        payloadJson("{\"anchor\": \"\(notAnAnchor)\", \"incremental\": true}")))
  }

  /// The page shape: a short page with no anchor to carry has no cursor and
  /// no commit token, and a full-history page carries no deletion keys.
  func testPagePayloadShortFullHistoryPageCarriesOnlySamples() {
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: nil,
      pageSize: 500,
      incremental: false,
      ownBundleId: nil)
    XCTAssertEqual((payload["samples"] as? [[String: Any]])?.count, 0)
    XCTAssertNil(payload["nextCursor"])
    XCTAssertNil(payload["commitToken"])
    XCTAssertNil(payload["incremental"])
    XCTAssertNil(payload["deletedRecordIds"])
  }

  /// An incremental page says so and carries the deleted ids — an empty
  /// list when HealthKit reported none — even on the empty page that means
  /// the store has nothing new. (`HKDeletedObject` has no public
  /// initializer, so a populated deleted-objects list cannot be constructed
  /// here; the UUID mapping is the one line between the query and the wire,
  /// and the Dart end-to-end suite covers the consumption side.)
  func testPagePayloadIncrementalPageCarriesTheDeletionKeys() {
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: nil,
      pageSize: 500,
      incremental: true,
      ownBundleId: nil)
    XCTAssertEqual((payload["samples"] as? [[String: Any]])?.count, 0)
    XCTAssertEqual(payload["incremental"] as? Bool, true)
    XCTAssertEqual(payload["deletedRecordIds"] as? [String], [])
    XCTAssertNil(payload["nextCursor"])
    XCTAssertNil(payload["commitToken"])
  }

  /// A full page (raw count reaching `pageSize`) with no anchor still
  /// fabricates no cursor: the page shape may claim more pages, but only
  /// with an anchor to resume from.
  func testPagePayloadFullPageWithoutAnchorCarriesNoCursor() {
    let sample = Self.menstrualFlowSample()
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [sample],
      deletedObjects: [],
      newAnchor: nil,
      pageSize: 1,
      incremental: false,
      ownBundleId: nil)
    XCTAssertEqual((payload["samples"] as? [[String: Any]])?.count, 1)
    XCTAssertNil(payload["nextCursor"])
    XCTAssertNil(payload["commitToken"])
  }

  /// An imported row's `sourceId` on iPhone is the sample's UUID, and the
  /// deletion reports must match it as-is — so a page's sample `recordId`
  /// must be exactly the sample UUID, with the flow intensity wire name the
  /// codec parses.
  func testPagePayloadSampleRecordIdIsTheSampleUuid() {
    let sample = Self.menstrualFlowSample()
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [sample],
      deletedObjects: [],
      newAnchor: nil,
      pageSize: 500,
      incremental: false,
      ownBundleId: nil)
    let samples = payload["samples"] as? [[String: Any]]
    XCTAssertEqual(samples?.count, 1)
    XCTAssertEqual(samples?.first?["recordId"] as? String, sample.uuid.uuidString)
    XCTAssertEqual(samples?.first?["flow"] as? String, "heavy")
    XCTAssertNotNil(samples?.first?["startMs"])
    XCTAssertNotNil(samples?.first?["endMs"])
  }

  /// A sample this app wrote comes back with the app's own bundle id as its
  /// source, and the page must drop it: re-importing our own writes would
  /// duplicate every entry and loop the write and read directions (#193's
  /// mandatory echo prevention). Naming another app keeps the sample. The
  /// drop is pinned by naming the in-memory sample's own source bundle id
  /// (a non-optional String on every HKSource): whatever the test host's
  /// source is named, the filter's equality decision is what is under test.
  func testPagePayloadDropsThisAppsOwnWrites() {
    let sample = Self.menstrualFlowSample()
    let otherApp = pagePayloadCount(
      sample, ownBundleId: "com.another.health-app")
    XCTAssertEqual(otherApp, 1, "another app's bundle id keeps the sample")
    let ownSource = pagePayloadCount(
      sample, ownBundleId: sample.sourceRevision.source.bundleIdentifier)
    XCTAssertEqual(ownSource, 0, "the sample's own source drops the sample")
  }

  /// One in-memory menstrual-flow sample: `HKMetadataKeyMenstrualCycleStart`
  /// is required on the type (the #193 rule the write path follows) — a
  /// sample without it fails object validation at construction. An
  /// in-memory sample carries no time-zone metadata, so the page maps it
  /// through the #902 device-zone fallback.
  private static func menstrualFlowSample() -> HKCategorySample {
    HKCategorySample(
      type: HKObjectType.categoryType(forIdentifier: .menstrualFlow)!,
      value: 4,
      start: Date(timeIntervalSince1970: 1_784_016_000),
      end: Date(timeIntervalSince1970: 1_784_101_599),
      metadata: [HKMetadataKeyMenstrualCycleStart: true])
  }

  private func pagePayloadCount(
    _ sample: HKCategorySample,
    ownBundleId: String?
  ) -> Int? {
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [sample],
      deletedObjects: [],
      newAnchor: nil,
      pageSize: 500,
      incremental: false,
      ownBundleId: ownBundleId)
    return (payload["samples"] as? [[String: Any]])?.count
  }
}
