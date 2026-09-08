import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import XCTest
@testable import DastakUI

@MainActor
final class DastakDeliveryRefreshTests: XCTestCase {
    func testUnrelatedServiceFailuresDoNotHideActiveDelivery() async {
        let functions = DeliveryRefreshFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.bootstrap()
        XCTAssertEqual(model.v1Dispatch?.currentMission?.displayOrderNumber, "D-123")
        XCTAssertEqual(
            model.v1Dispatch?.currentMission?.pickupStops.first?.branch.address.displayLine,
            "128, Mandi Street, Vaniyambadi"
        )
        XCTAssertTrue(model.hasActiveJob)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotNil(model.refreshFailure)
        XCTAssertNil(model.errorMessage, "Background reconnection must not present a blocking alert")
    }

    func testFailedRefreshRetainsLastKnownJobUntilSuccessfulEmptySnapshot() async {
        let functions = DeliveryRefreshFunctionsStub()
        let model = DastakDeliveryPartnerModel(functions: functions)
        await model.refresh()
        await functions.setResponse(.failure)
        await model.refresh()
        XCTAssertTrue(model.hasActiveJob)
        await functions.setResponse(.empty)
        await model.refresh()
        XCTAssertFalse(model.hasActiveJob)
        XCTAssertNil(model.v1Dispatch?.currentMission)
    }
}

private actor DeliveryRefreshFunctionsStub: FunctionClient {
    enum Response { case mission, empty, failure }
    private var response: Response = .mission
    func setResponse(_ response: Response) { self.response = response }

    func invoke<Request: Encodable & Sendable, Result: Decodable & Sendable>(
        _ name: String, request: Request, idempotencyKey: IdempotencyKey
    ) async throws -> Result {
        let encoded = try JSONEncoder().encode(request)
        let body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        guard body?["operation"] as? String == "v1PartnerSnapshot", response != .failure else {
            throw URLError(.notConnectedToInternet)
        }
        let json = response == .empty ? "{}" : """
        {"currentMission":{
          "id":"00000000-0000-0000-0000-000000000001",
          "displayOrderNumber":"D-123","status":"ASSIGNED","version":1,
          "pickupCount":1,"pickupStops":[{
            "id":"00000000-0000-0000-0000-000000000002",
            "sequence":1,"status":"PENDING","ready":true,"runningLate":false,
            "packageCount":1,"waitingSeconds":0,
            "branch":{
              "id":"00000000-0000-0000-0000-000000000003",
              "displayName":"Zuper",
              "address":{
                "line1":"128, Mandi Street, Vaniyambadi",
                "latitude":12.6811386362372,"longitude":78.6154330651743
              },
              "location":{"latitude":12.6811386362372,"longitude":78.6154330651743}
            }
          }],"canStartFinalDelivery":false,
          "canArriveCustomer":false,"canCaptureDeliveryEvidence":false,
          "canVerifyDelivery":false,"canCancelBeforePickup":true,
          "mustUseDeliveryRecovery":false
        }}
        """
        return try JSONDecoder().decode(Result.self, from: Data(json.utf8))
    }
}
