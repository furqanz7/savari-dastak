import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakAddressSelectionTests: XCTestCase {
    func testCheckoutSelectionIsReadOnlyAndDefaultSurvivesRefreshAndRelaunch() async throws {
        let functions = AddressSelectionFunctions()
        let model = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await model.bootstrap()
        let original = try XCTUnwrap(model.defaultDeliveryAddress)
        let work = try XCTUnwrap(model.savedAddresses.first { $0.label == "Work" })
        let selected = await model.selectSavedAddress(work, makeDefault: false)
        XCTAssertTrue(selected)
        XCTAssertEqual(model.deliveryAddress?.addressID, work.addressID)
        XCTAssertEqual(model.defaultDeliveryAddress, original)
        XCTAssertTrue(model.availabilityRefreshKey.contains(try XCTUnwrap(work.addressID).uuidString))
        await model.bootstrap()
        XCTAssertEqual(model.deliveryAddress?.addressID, work.addressID)
        XCTAssertEqual(model.defaultDeliveryAddress, original)
        let relaunched = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await relaunched.bootstrap()
        XCTAssertEqual(relaunched.defaultDeliveryAddress, original)
        XCTAssertEqual(relaunched.deliveryAddress, original)
        let writes = await functions.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testNewCheckoutAddressIsSavedWithoutReplacingDefault() async throws {
        let functions = AddressSelectionFunctions()
        let model = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await model.bootstrap()
        let original = model.defaultDeliveryAddress
        let saved = await model.setLocation(.init(address: "Third Road", point: .init(latitude: 12.7, longitude: 78.7),
                                                  label: "Other", building: "Block C"), makeDefault: false)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.defaultDeliveryAddress, original)
        XCTAssertEqual(model.deliveryAddress?.address, "Third Road")
        XCTAssertNotNil(model.deliveryAddress?.addressVersion)
        let flags = await functions.saveDefaultFlags
        XCTAssertEqual(flags, [false])
        let relaunched = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await relaunched.bootstrap()
        XCTAssertEqual(relaunched.defaultDeliveryAddress, original)
        XCTAssertEqual(relaunched.savedAddresses.count, 3)
    }

    func testAccountSelectionStillExplicitlyChangesDefault() async throws {
        let functions = AddressSelectionFunctions()
        let model = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await model.bootstrap()
        let work = try XCTUnwrap(model.savedAddresses.first { $0.label == "Work" })
        let selected = await model.selectSavedAddress(work)
        XCTAssertTrue(selected)
        XCTAssertEqual(model.defaultDeliveryAddress?.addressID, work.addressID)
        XCTAssertEqual(model.deliveryAddress?.addressID, work.addressID)
        let writes = await functions.writes
        XCTAssertEqual(writes, ["setDefault"])
    }

    func testEditingCheckoutAddressAndDeletingAnotherPreservesBothSelections() async throws {
        let functions = AddressSelectionFunctions()
        let model = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await model.bootstrap()
        let original = model.defaultDeliveryAddress
        let work = try XCTUnwrap(model.savedAddresses.first { $0.label == "Work" })
        let result = await model.setLocation(.init(addressID: work.addressID, address: "Updated Work Road",
            point: work.point, label: "Work", building: "Block B"), makeDefault: false)
        XCTAssertTrue(result)
        XCTAssertEqual(model.deliveryAddress?.addressID, work.addressID)
        XCTAssertEqual(model.deliveryAddress?.address, "Updated Work Road")
        XCTAssertEqual(model.defaultDeliveryAddress, original)
        let deleted = await model.deleteSavedAddress(try XCTUnwrap(model.deliveryAddress))
        XCTAssertTrue(deleted)
        XCTAssertEqual(model.deliveryAddress, original)
        XCTAssertEqual(model.defaultDeliveryAddress, original)
    }

    func testFailedCheckoutReadCannotChangeAddressOrWriteDefault() async throws {
        let functions = AddressSelectionFunctions()
        let model = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await model.bootstrap()
        let original = model.deliveryAddress
        let work = try XCTUnwrap(model.savedAddresses.first { $0.label == "Work" })
        await functions.failRead()
        let selected = await model.selectSavedAddress(work, makeDefault: false)
        XCTAssertFalse(selected)
        XCTAssertEqual(model.deliveryAddress, original)
        XCTAssertEqual(model.defaultDeliveryAddress, original)
        XCTAssertNotNil(model.addressErrorMessage)
        let writes = await functions.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testDeletingUnselectedAddressKeepsCheckoutTargetAndDefault() async throws {
        let functions = AddressSelectionFunctions()
        let model = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await model.bootstrap()
        let original = model.defaultDeliveryAddress
        let work = try XCTUnwrap(model.savedAddresses.first { $0.label == "Work" })
        let saved = await model.setLocation(.init(address: "Third Road", point: .init(latitude: 12.7, longitude: 78.7),
                                                  label: "Other", building: "Block C"), makeDefault: false)
        XCTAssertTrue(saved)
        let target = model.deliveryAddress
        let deleted = await model.deleteSavedAddress(work)
        XCTAssertTrue(deleted)
        XCTAssertEqual(model.deliveryAddress, target)
        XCTAssertEqual(model.defaultDeliveryAddress, original)
    }

    func testStaleDeletedAddressCannotBeSelectedForCheckout() async throws {
        let functions = AddressSelectionFunctions()
        let model = DastakCustomerModel(functions: functions, enforcesAreaChecks: false)
        await model.bootstrap()
        let original = model.deliveryAddress
        let work = try XCTUnwrap(model.savedAddresses.first { $0.label == "Work" })
        await functions.removeWork()
        let selected = await model.selectSavedAddress(work, makeDefault: false)
        XCTAssertFalse(selected)
        XCTAssertEqual(model.deliveryAddress, original)
        XCTAssertEqual(model.defaultDeliveryAddress, original)
        let writes = await functions.writes
        XCTAssertTrue(writes.isEmpty)
    }
}

private actor AddressSelectionFunctions: FunctionClient {
    private var addresses: [[String: Any]] = [
        ["addressId": "11111111-1111-4111-8111-111111111111", "label": "Home", "address": "Test Road",
         "building": "1", "details": "1", "displayAddress": "1 Test Road",
         "location": ["latitude": 12.68, "longitude": 78.62], "isDefault": true, "updatedAt": "2026-10-15T00:00:00Z"],
        ["addressId": "22222222-2222-4222-8222-222222222222", "label": "Work", "address": "Work Road",
         "building": "2", "details": "2", "displayAddress": "2 Work Road",
         "location": ["latitude": 12.69, "longitude": 78.63], "isDefault": false, "updatedAt": "2026-10-15T00:00:00Z"]
    ]
    private(set) var writes: [String] = []
    private(set) var saveDefaultFlags: [Bool] = []
    private var failsRead = false
    func failRead() { failsRead = true }
    func removeWork() { addresses.removeAll { $0["label"] as? String == "Work" } }

    func invoke<Input: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Input, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        guard name == "customer-addresses" else { throw URLError(.unsupportedURL) }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let operation = body["operation"] as? String ?? "snapshot"
        if operation == "snapshot", failsRead { throw URLError(.notConnectedToInternet) }
        if operation != "snapshot" { writes.append(operation) }
        if operation == "setDefault" {
            for index in addresses.indices { addresses[index]["isDefault"] = addresses[index]["addressId"] as? String == body["addressId"] as? String }
        } else if operation == "save" {
            let makeDefault = body["makeDefault"] as? Bool == true
            saveDefaultFlags.append(makeDefault)
            let id = body["addressId"] as? String ?? "33333333-3333-4333-8333-333333333333"
            let wasDefault = addresses.contains { $0["addressId"] as? String == id && $0["isDefault"] as? Bool == true }
            if makeDefault { for index in addresses.indices { addresses[index]["isDefault"] = false } }
            addresses.removeAll { $0["addressId"] as? String == id }
            var saved = body
            saved["addressId"] = id
            saved["isDefault"] = makeDefault || wasDefault
            saved["details"] = body["building"]
            saved["displayAddress"] = body["address"]
            saved["updatedAt"] = "2026-10-15T00:00:01Z"
            addresses.append(saved)
        } else if operation == "delete" {
            addresses.removeAll { $0["addressId"] as? String == body["addressId"] as? String }
        }
        return try JSONDecoder().decode(Result.self, from: JSONSerialization.data(withJSONObject: ["addresses": addresses]))
    }
}
