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

    func testAuthorizedNumberAllowsCallWithoutLiveGPS() throws {
        let tracking = try decodeTracking(location: NSNull(), phone: "+919999999999")
        XCTAssertFalse(tracking.isLive(at: now))
        for status in ["PAID", "PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY"] {
            XCTAssertEqual(tracking.customerCallURL(orderStatus: status)?.absoluteString, "tel:+919999999999")
        }
        let delayed = try decodeTracking(phone: "+919999999999")
        XCTAssertFalse(delayed.isLive(at: now.addingTimeInterval(31)))
        XCTAssertNotNil(delayed.customerCallURL(orderStatus: "OUT_FOR_DELIVERY"))
    }

    func testTerminalOrUnconfirmedOrdersNeverExposeCachedContact() throws {
        let tracking = try decodeTracking(phone: "+919999999999")
        for status in ["DELIVERED", "CANCELLED", "FAILED", "EXPIRED", "SUBMITTED", "AWAITING_PAYMENT", "UNKNOWN"] {
            XCTAssertNil(tracking.customerCallURL(orderStatus: status))
        }
    }

    func testTerminalOrUnknownMissionNeverAllowsCall() throws {
        for phase in ["COMPLETED", "CANCELLED", "UNASSIGNED", "UNKNOWN"] {
            XCTAssertNil(try decodeTracking(phone: "+919999999999", phase: phase)
                .customerCallURL(orderStatus: "OUT_FOR_DELIVERY"))
        }
    }

    func testUnsafeOrMalformedContactDoesNotPreventTrackingDecode() throws {
        for phone: Any in ["javascript:alert(1)", "+919999999999\n", "+919999999999;123", "919999999999",
                           "+0123456789", "+1234567", "+1234567890123456", "+٩١٩٩٩٩٩٩٩٩٩٩", 123, ["number": "123"], NSNull()] {
            let tracking = try decodeTracking(phone: phone)
            XCTAssertNil(tracking.riderPhoneNumber)
            XCTAssertNil(tracking.customerCallURL(orderStatus: "OUT_FOR_DELIVERY"))
        }
    }

    func testOlderResponseAndContactRemovalDoNotInventPhoneNumber() throws {
        let initial = try decodeTracking(phone: "+919999999999")
        XCTAssertNotNil(initial.customerCallURL(orderStatus: "OUT_FOR_DELIVERY"))
        let refreshed = try decodeTracking()
        XCTAssertNil(refreshed.riderPhoneNumber)
        XCTAssertNil(refreshed.customerCallURL(orderStatus: "OUT_FOR_DELIVERY"))
    }

    func testValidTrackingPhoneSurvivesCodableRoundTrip() throws {
        let tracking = try decodeTracking(phone: "+919999999999")
        let restored = try JSONDecoder().decode(DastakDeliveryTracking.self, from: JSONEncoder().encode(tracking))
        XCTAssertEqual(restored, tracking)
    }

    private func eligibility(_ eligible: Bool) throws -> DastakArrivalEligibility {
        try JSONDecoder().decode(DastakArrivalEligibility.self, from: JSONSerialization.data(withJSONObject: [
            "eligible": eligible, "reason": eligible ? "ELIGIBLE" : "LOCATION_INACCURATE",
            "distanceMeters": 2, "radiusMeters": 50, "validUntil": now.addingTimeInterval(30).ISO8601Format(),
        ]))
    }

    private func decodeTracking(accuracy: Double = 5, location: Any = ["latitude":12.68,"longitude":78.62],
                                recorded: Date? = nil, phone: Any? = nil, phase: String = "ASSIGNED") throws -> DastakDeliveryTracking {
        var body: [String: Any] = [
            "missionId": UUID().uuidString, "phase": phase, "riderName": "Delivery Partner",
            "location": location, "accuracyMeters": accuracy,
            "recordedAt": (recorded ?? now).ISO8601Format(), "receivedAt": now.ISO8601Format(),
            "serverTime": now.ISO8601Format(), "liveUntil": now.addingTimeInterval(30).ISO8601Format(),
        ]
        if let phone { body["riderPhoneNumber"] = phone }
        return try JSONDecoder().decode(DastakDeliveryTracking.self, from: JSONSerialization.data(withJSONObject: body))
    }
}
