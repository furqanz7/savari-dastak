import Foundation
import MarketplaceInfrastructure
import XCTest

final class DastakDeliveryTrackingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    func testLocationExpiresWithoutNeedingAnotherNetworkResponse() throws {
        let tracking = try decodeTracking()
        XCTAssertTrue(tracking.isLive(at: now))
        XCTAssertFalse(tracking.isLive(at: now.addingTimeInterval(31)))
    }

    func testCoarseMissingAndFuturePositionsAreNotPresentedAsLive() throws {
        XCTAssertFalse(try decodeTracking(accuracy: 80).isLive(at: now))
        XCTAssertFalse(try decodeTracking(location: NSNull()).isLive(at: now))
        XCTAssertFalse(try decodeTracking(recorded: now.addingTimeInterval(20)).isLive(at: now))
    }

    func testServerEligibilityExpiresAndCannotBeInferredFromDistanceAlone() throws {
        let allowed = try eligibility(true)
        XCTAssertTrue(allowed.canArrive(at: now))
        XCTAssertFalse(allowed.canArrive(at: now.addingTimeInterval(31)))
        XCTAssertFalse(try eligibility(false).canArrive(at: now))
        let missing = try JSONDecoder().decode(DastakArrivalEligibility.self,
            from: Data(#"{"eligible":true,"reason":"ELIGIBLE","radiusMeters":50}"#.utf8))
        XCTAssertFalse(missing.canArrive(at: now))
    }

    func testLocationUploadIncludesMissionSampleTimeAndAccuracyNotActorIdentity() throws {
        let sample = DastakMissionLocationSample(missionId: UUID(), latitude: 12.68,
            longitude: 78.62, accuracyMeters: 7, recordedAt: now)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        XCTAssertEqual(body["operation"] as? String, "v1PublishLocation")
        XCTAssertEqual(body["accuracyMeters"] as? Double, 7)
        XCTAssertNil(body["accountId"])
        XCTAssertEqual(DastakDeliveryTracking.date(body["recordedAt"] as? String), now)
    }

    private func eligibility(_ eligible: Bool) throws -> DastakArrivalEligibility {
        try JSONDecoder().decode(DastakArrivalEligibility.self, from: JSONSerialization.data(withJSONObject: [
            "eligible": eligible, "reason": eligible ? "ELIGIBLE" : "LOCATION_INACCURATE",
            "distanceMeters": 2, "radiusMeters": 50, "validUntil": now.addingTimeInterval(30).ISO8601Format(),
        ]))
    }

    private func decodeTracking(accuracy: Double = 5, location: Any = ["latitude":12.68,"longitude":78.62],
                                recorded: Date? = nil) throws -> DastakDeliveryTracking {
        try JSONDecoder().decode(DastakDeliveryTracking.self, from: JSONSerialization.data(withJSONObject: [
            "missionId": UUID().uuidString, "phase": "ASSIGNED", "riderName": "Delivery Partner",
            "location": location, "accuracyMeters": accuracy,
            "recordedAt": (recorded ?? now).ISO8601Format(), "receivedAt": now.ISO8601Format(),
            "serverTime": now.ISO8601Format(), "liveUntil": now.addingTimeInterval(30).ISO8601Format(),
        ]))
    }
}
