import Foundation
import MarketplaceFoundation
import XCTest
@testable import DastakUI

final class DastakPinSelectionTests: XCTestCase {
    @MainActor
    func testMovingPinDropsOldStreetAndSavedIdentityImmediately() throws {
        let saved = DastakDeliveryLocation(addressID: UUID(), addressVersion: "old", address: "Old Street",
                                           point: .init(latitude: 12, longitude: 78), label: "Home", building: "12")
        let model = DastakPinSelection(location: saved)
        let token = try XCTUnwrap(model.beginMove(latitude: 12.3, longitude: 78.4))
        XCTAssertTrue(model.isResolving)
        XCTAssertEqual(model.location?.point, GeoPoint(latitude: 12.3, longitude: 78.4))
        XCTAssertEqual(model.location?.address, "Pinned location")
        XCTAssertNil(model.location?.addressID)
        XCTAssertNil(model.location?.addressVersion)
        XCTAssertNil(model.location?.building)
        model.finishMove(token, address: "  New Street  ")
        XCTAssertEqual(model.location?.address, "New Street")
        XCTAssertFalse(model.isResolving)
    }

    @MainActor
    func testLateGeocodingCannotReplaceNewerPin() throws {
        let model = DastakPinSelection(location: nil)
        let old = try XCTUnwrap(model.beginMove(latitude: 12, longitude: 78))
        let new = try XCTUnwrap(model.beginMove(latitude: 13, longitude: 79))
        model.finishMove(old, address: "Stale street")
        XCTAssertTrue(model.isResolving)
        XCTAssertEqual(model.location?.address, "Pinned location")
        model.finishMove(new, address: "Current street")
        XCTAssertEqual(model.location?.point, GeoPoint(latitude: 13, longitude: 79))
        XCTAssertEqual(model.location?.address, "Current street")
    }

    @MainActor
    func testChoosingSearchResultSupersedesPendingPinLookup() throws {
        let model = DastakPinSelection(location: nil)
        let token = try XCTUnwrap(model.beginMove(latitude: 12, longitude: 78))
        let searched = DastakDeliveryLocation(address: "Search result", point: .init(latitude: 14, longitude: 77))
        model.select(searched)
        model.finishMove(token, address: "Late street")
        XCTAssertEqual(model.location, searched)
        XCTAssertFalse(model.isResolving)
    }

    @MainActor
    func testFailedStreetLookupRetainsExactPinAndExplainsFallback() throws {
        let model = DastakPinSelection(location: nil)
        let token = try XCTUnwrap(model.beginMove(latitude: 12.12345, longitude: 78.12345))
        model.finishMove(token, address: " \n ")
        XCTAssertEqual(model.location?.address, "Pinned location")
        XCTAssertEqual(model.location?.point, GeoPoint(latitude: 12.12345, longitude: 78.12345))
        XCTAssertNotNil(model.notice)
        XCTAssertFalse(model.isResolving)
    }

    @MainActor
    func testRejectsNonfiniteAndOutOfRangeCoordinatesWithoutLosingSelection() {
        let saved = DastakDeliveryLocation(address: "Street", point: .init(latitude: 12, longitude: 78))
        let model = DastakPinSelection(location: saved)
        for (lat, lon) in [(Double.nan, 78.0), (12.0, Double.infinity), (91.0, 78.0), (12.0, -181.0)] {
            XCTAssertNil(model.beginMove(latitude: lat, longitude: lon))
            XCTAssertEqual(model.location, saved)
            XCTAssertFalse(model.isResolving)
        }
    }

    @MainActor
    func testDismissalInvalidatesPendingLookup() throws {
        let model = DastakPinSelection(location: nil)
        let token = try XCTUnwrap(model.beginMove(latitude: 12, longitude: 78))
        model.invalidatePendingMove()
        model.finishMove(token, address: "Late result after dismissal")
        XCTAssertEqual(model.location?.address, "Pinned location")
        XCTAssertFalse(model.isResolving)
    }
}
