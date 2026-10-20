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

  /// Issue #1590: the write types no sheet has asked about — the
  /// `.notDetermined` ones, and no others. A type the person denied or
  /// allowed is never offered again, and every written type must map to a
  /// wire name: a type added without one would be silently skipped by the
  /// ask the Health sync screen raises for it.
  func testNeverAskedWriteTypesAreOnlyTheNotDeterminedOnes() {
    // Every written type answers .notDetermined with a wire name — the
    // same set `grantedWriteTypes` speaks.
    let allWires = Set(
      HealthKitChannelHandler.writtenSampleTypes.compactMap {
        HealthKitChannelHandler.wireIdentifier(for: $0)
      })
    let neverAsked = HealthKitChannelHandler.neverAskedWriteTypeWires {
      _ in .notDetermined
    }
    XCTAssertEqual(Set(neverAsked), allWires)
    XCTAssertTrue(neverAsked.contains("menstrualFlow"))
    XCTAssertTrue(neverAsked.contains("spotting"))
    XCTAssertTrue(neverAsked.contains("cervicalMucus"))
    XCTAssertTrue(neverAsked.contains("ovulationTest"))
    XCTAssertTrue(neverAsked.contains("basalBodyTemperature"))
    XCTAssertTrue(neverAsked.contains("headache"))
    XCTAssertFalse(
      neverAsked.contains("symptoms"),
      "the all-on aggregate is not a type any sheet asks about")

    // A determined type is never in the answer: denied or allowed, the
    // person has answered for it.
    XCTAssertTrue(
      HealthKitChannelHandler.neverAskedWriteTypeWires {
        _ in .sharingDenied
      }.isEmpty)
    XCTAssertTrue(
      HealthKitChannelHandler.neverAskedWriteTypeWires {
        _ in .sharingAuthorized
      }.isEmpty)

    // A mixed store: exactly the notDetermined one is offered.
    let mixed = HealthKitChannelHandler.neverAskedWriteTypeWires {
      HealthKitChannelHandler.wireIdentifier(for: $0) == "spotting"
        ? .notDetermined : .sharingDenied
    }
    XCTAssertEqual(mixed, ["spotting"])
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
  /// no commit token, and carries deletedRecordIds (Issue #1651: HealthKit
  /// reports deletions even on non-incremental initial queries).
  func testPagePayloadShortFullHistoryPageCarriesDeletedRecordIds() {
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
    XCTAssertEqual(payload["deletedRecordIds"] as? [String], [])
  }

  /// Issue #1650, #1905: an empty whole-history page must not carry a commitToken even
  /// when an anchor is returned. If read access was off, HealthKit silently returns
  /// empty with an anchor (or with only lunarlog's own deleted writes, which cannot
  /// be source-filtered); committing it would leave past history unimported once
  /// access is enabled.
  func testPagePayloadEmptyWholeHistoryWithAnchorEmitsNoCommitToken() {
    let anchor = HKQueryAnchor(fromValue: 42)
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: anchor,
      pageSize: 500,
      incremental: false,
      ownBundleId: nil)
    XCTAssertEqual((payload["samples"] as? [[String: Any]])?.count, 0)
    XCTAssertNil(payload["nextCursor"])
    XCTAssertNil(payload["commitToken"], "empty whole history read must not commit anchor (#1650, #1905)")
  }

  /// In contrast, an empty incremental page DOES carry commitToken to advance
  /// position after an idle sync.
  func testPagePayloadEmptyIncrementalWithAnchorCarriesCommitToken() {
    let anchor = HKQueryAnchor(fromValue: 42)
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: anchor,
      pageSize: 500,
      incremental: true,
      ownBundleId: nil)
    XCTAssertEqual((payload["samples"] as? [[String: Any]])?.count, 0)
    XCTAssertNil(payload["nextCursor"])
    XCTAssertNotNil(payload["commitToken"], "incremental read can advance anchor when empty")
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


  // MARK: - Issue #1888: Intermenstrual bleeding (spotting) read and multi-stage paging

  /// Issue #1888: An imported intermenstrual bleeding sample maps to kind "intermenstrualBleeding"
  /// with recordId equal to sample UUID, startMs, endMs, and no flow intensity key.
  func testPagePayloadIntermenstrualBleedingSample() {
    let sample = Self.intermenstrualBleedingSample()
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
    XCTAssertEqual(samples?.first?["kind"] as? String, "intermenstrualBleeding")
    XCTAssertNil(samples?.first?["flow"], "intermenstrual bleeding has no flow intensity")
    XCTAssertNotNil(samples?.first?["startMs"])
    XCTAssertNotNil(samples?.first?["endMs"])
  }

  /// Issue #1888: An intermenstrual bleeding sample written by lunarlog itself is dropped by the
  /// echo filter, while a sample from another app is preserved.
  func testPagePayloadDropsIntermenstrualBleedingOwnWrites() {
    let sample = Self.intermenstrualBleedingSample()
    let otherApp = pagePayloadCount(
      sample, ownBundleId: "com.another.health-app")
    XCTAssertEqual(otherApp, 1, "another app's bundle id keeps the spotting sample")
    let ownSource = pagePayloadCount(
      sample, ownBundleId: sample.sourceRevision.source.bundleIdentifier)
    XCTAssertEqual(ownSource, 0, "the sample's own source drops the spotting sample")
  }

  /// Issue #1888: When the menstrual flow query is exhausted (count < pageSize), the page
  /// transitions to stage .spotting with nextCursor, carrying forward the new flow anchor.
  func testMultiStageCursorTransitionFlowToSpotting() {
    let anchor = HKQueryAnchor(fromValue: 101)
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: anchor,
      pageSize: 500,
      incremental: false,
      ownBundleId: nil,
      stage: .flow,
      flowAnchor: anchor,
      spottingAnchor: nil,
      passHadSamples: false)

    XCTAssertNil(payload["commitToken"])
    guard let nextCursor = payload["nextCursor"] as? String else {
      XCTFail("Expected nextCursor transitioning to spotting stage")
      return
    }
    guard let decoded = HealthKitChannelHandler.decodeAnchorPayload(nextCursor) else {
      XCTFail("Expected valid decoded cursor")
      return
    }
    XCTAssertEqual(decoded.stage, .spotting)
    XCTAssertNotNil(decoded.flowAnchor)
    XCTAssertNil(decoded.spottingAnchor)
    XCTAssertFalse(decoded.passHadSamples)
  }

  /// Issue #1888: When the spotting query is exhausted, the pass terminates (nextCursor == nil)
  /// and commits both flow and spotting anchors.
  func testMultiStageCursorSpottingExhaustionTerminates() {
    let flowAnchor = HKQueryAnchor(fromValue: 101)
    let spottingAnchor = HKQueryAnchor(fromValue: 202)
    let payload = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: spottingAnchor,
      pageSize: 500,
      incremental: true,
      ownBundleId: nil,
      stage: .spotting,
      flowAnchor: flowAnchor,
      spottingAnchor: spottingAnchor,
      passHadSamples: false)

    XCTAssertNil(payload["nextCursor"])
    guard let commitToken = payload["commitToken"] as? String else {
      XCTFail("Expected commitToken on incremental pass completion")
      return
    }
    guard let decoded = HealthKitChannelHandler.decodeAnchorPayload(commitToken) else {
      XCTFail("Expected valid decoded commitToken")
      return
    }
    XCTAssertEqual(decoded.stage, .spotting)
    XCTAssertNotNil(decoded.flowAnchor)
    XCTAssertNotNil(decoded.spottingAnchor)
  }

  /// Issue #1888: Legacy stored anchor payloads (which only carried "anchor" for flow)
  /// decode flowAnchor and leave spottingAnchor as nil. Starting an incremental page from it
  /// begins at stage .flow with flowAnchor set and spottingAnchor nil, so the subsequent
  /// spotting pass will do a clean full read of spotting history without requiring a manual reset.
  func testLegacyAnchorUpgradeDecoding() {
    let anchor = HKQueryAnchor(fromValue: 42)
    guard let legacyCursor = HealthKitChannelHandler.cursorString(for: anchor) else {
      XCTFail("Failed to serialize anchor")
      return
    }
    let json: [String: Any] = [
      "anchor": legacyCursor,
      "incremental": true,
    ]
    let jsonData = try! JSONSerialization.data(withJSONObject: json)
    let legacyPayload = HealthKitChannelHandler.encodeCursorData(jsonData)

    guard let decoded = HealthKitChannelHandler.decodeAnchorPayload(legacyPayload) else {
      XCTFail("Failed to decode legacy payload")
      return
    }
    XCTAssertEqual(decoded.stage, .flow)
    XCTAssertTrue(decoded.incremental)
    XCTAssertNotNil(decoded.flowAnchor)
    XCTAssertNil(decoded.spottingAnchor)

    HealthKitChannelHandler.storeImportAnchor(anchorProfileA, legacyPayload)
    let startPage = HealthKitChannelHandler.startingPage(
      profileId: anchorProfileA, cursor: nil, wholeHistory: false)
    XCTAssertEqual(startPage.stage, .flow)
    XCTAssertTrue(startPage.incremental)
    XCTAssertNotNil(startPage.flowAnchor)
    XCTAssertNil(startPage.spottingAnchor)
  }

  /// Issue #1888, #1650, #1905: An empty whole-history pass (no flow samples, no spotting samples)
  /// does not commit an anchor on either stage, protecting past history when read access is denied.
  func testTwoStageEmptyWholeHistoryDoesNotCommit() {
    let flowAnchor = HKQueryAnchor(fromValue: 1)
    let spottingAnchor = HKQueryAnchor(fromValue: 2)

    // Stage 1 (flow) empty:
    let stage1 = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: flowAnchor,
      pageSize: 500,
      incremental: false,
      ownBundleId: nil,
      stage: .flow,
      flowAnchor: flowAnchor,
      spottingAnchor: nil,
      passHadSamples: false)
    XCTAssertNil(stage1["commitToken"])
    let nextCursor = stage1["nextCursor"] as? String
    XCTAssertNotNil(nextCursor)

    // Stage 2 (spotting) empty:
    let stage2 = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: spottingAnchor,
      pageSize: 500,
      incremental: false,
      ownBundleId: nil,
      stage: .spotting,
      flowAnchor: flowAnchor,
      spottingAnchor: spottingAnchor,
      passHadSamples: false)
    XCTAssertNil(stage2["nextCursor"])
    XCTAssertNil(stage2["commitToken"], "empty whole history read must not commit anchor (#1650, #1888, #1905)")
  }

  /// Issue #1888: A whole-history pass with no flow samples but with foreign spotting samples
  /// carries passHadSamples and commits an anchor once the spotting stage finishes.
  func testTwoStageWholeHistoryWithSpottingDataCommits() {
    let flowAnchor = HKQueryAnchor(fromValue: 1)
    let spottingAnchor = HKQueryAnchor(fromValue: 2)
    let sample = Self.intermenstrualBleedingSample()

    // Stage 1 (flow) empty:
    let stage1 = HealthKitChannelHandler.pagePayload(
      samples: [],
      deletedObjects: [],
      newAnchor: flowAnchor,
      pageSize: 500,
      incremental: false,
      ownBundleId: nil,
      stage: .flow,
      flowAnchor: flowAnchor,
      spottingAnchor: nil,
      passHadSamples: false)
    XCTAssertNil(stage1["commitToken"])
    guard let nextCursor = stage1["nextCursor"] as? String,
          let decodedCursor = HealthKitChannelHandler.decodeAnchorPayload(nextCursor) else {
      XCTFail("Expected valid nextCursor")
      return
    }

    // Stage 2 (spotting) has sample:
    let stage2 = HealthKitChannelHandler.pagePayload(
      samples: [sample],
      deletedObjects: [],
      newAnchor: spottingAnchor,
      pageSize: 500,
      incremental: false,
      ownBundleId: "com.another.health-app",
      stage: decodedCursor.stage,
      flowAnchor: decodedCursor.flowAnchor,
      spottingAnchor: spottingAnchor,
      passHadSamples: decodedCursor.passHadSamples)
    XCTAssertNil(stage2["nextCursor"])
    XCTAssertNotNil(stage2["commitToken"], "whole history pass with spotting samples must commit anchor (#1888)")
  }

  /// One in-memory intermenstrual-bleeding (spotting) sample for testing.
  private static func intermenstrualBleedingSample() -> HKCategorySample {
    HKCategorySample(
      type: HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding)!,
      value: HKCategoryValue.notApplicable.rawValue,
      start: Date(timeIntervalSince1970: 1_784_016_000),
      end: Date(timeIntervalSince1970: 1_784_016_000),
      metadata: nil)
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
