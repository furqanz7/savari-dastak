import Foundation
import MarketplaceFoundation
import XCTest
@testable import MarketplaceInfrastructure

final class DastakV1AdminClientTests: XCTestCase {
    func testLiveOrdersAndTraceDecodeProductionResponseShape() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)

        let orders = try await client.orders(limit: 50, idempotencyKey: key("admin-orders"))
        let order = try XCTUnwrap(orders.first)
        XCTAssertEqual(order.displayOrderNumber, "DSK-260903-00000052")
        XCTAssertEqual(order.status, "PREPARING")
        XCTAssertEqual(order.version, 9)
        var request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "adminExecutionOrders")
        XCTAssertEqual(request["limit"] as? Int, 50)

        let trace = try await client.trace(orderID: order.id, idempotencyKey: key("admin-trace"))
        XCTAssertEqual(trace.order.id, order.id)
        XCTAssertEqual(trace.launchPayment?.collectionStatus, "DUE")
        XCTAssertEqual(trace.launchPayment?.commitment?.amountPaise, 58_500)
        request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "adminExecutionTrace")
        XCTAssertEqual(request["orderId"] as? String, order.id.uuidString.uppercased())
    }

    func testAccessDecodesFixedSuperadminAndExecutiveSlots() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let access = try await client.access(idempotencyKey: key("admin-access"))

        XCTAssertEqual(access.role, .superadmin)
        XCTAssertTrue(access.canManageAdmins)
        XCTAssertEqual(access.slots.map(\.slot), [0, 1, 2])
        XCTAssertEqual(access.slots[1].role, .executiveAdmin)
        XCTAssertNil(access.slots[1].email)
        let request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "adminAccess")
        XCTAssertNil(request["accountId"])
    }

    func testExecutiveAssignmentSendsOnlySlotEmailVersionAndReason() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let slot = try await client.setExecutiveAdmin(
            slot: 1,
            email: "executive@example.com",
            expectedVersion: 1,
            reason: "Updated from protected Dastak Admin access settings.",
            idempotencyKey: key("admin-assign")
        )

        XCTAssertEqual(slot.email, "executive@example.com")
        XCTAssertTrue(slot.linked)
        let request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "setExecutiveAdmin")
        XCTAssertEqual(request["slot"] as? Int, 1)
        XCTAssertEqual(request["expectedVersion"] as? Int, 1)
        XCTAssertNil(request["accountId"])
        XCTAssertNil(request["role"])
    }

    func testCommandCenterAndNetworkDecodeConnectedAdminState() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)

        let commandCenter = try await client.commandCenter(idempotencyKey: key("admin-center"))
        XCTAssertEqual(commandCenter.actionQueue.merchantApplications, 2)
        XCTAssertEqual(commandCenter.commerce.activeOrders, 7)
        XCTAssertEqual(commandCenter.catalogue.total, 3_637)
        var request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "adminCommandCenter")
        XCTAssertNil(request["accountId"])

        let cursor = DastakAdminNetworkCursor(
            updatedAt: "2026-08-31T12:34:56Z",
            accountId: try XCTUnwrap(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        )
        let page = try await client.networkPage(
            query: "Furqan",
            persona: .merchant,
            state: .active,
            limit: 40,
            cursor: cursor,
            idempotencyKey: key("admin-network")
        )
        XCTAssertEqual(page.people.first?.displayName, "Furqan")
        XCTAssertEqual(page.people.first?.merchant?.businessName, "Dastak Store")
        XCTAssertTrue(page.hasMore)
        request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "adminNetworkPage")
        XCTAssertEqual(request["query"] as? String, "Furqan")
        XCTAssertEqual(request["persona"] as? String, "MERCHANT")
        XCTAssertEqual(request["state"] as? String, "ACTIVE")
        XCTAssertEqual(request["limit"] as? Int, 40)
        XCTAssertNil(request["accountId"])
    }

    func testCataloguePageAndMutationUseCatalogueBoundaryAndOptimisticVersion() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let skuID = try XCTUnwrap(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let categoryTypeID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
        let categoryID = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))
        let subcategoryID = try XCTUnwrap(UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))

        let taxonomy = try await client.catalogueTaxonomy(idempotencyKey: key("admin-taxonomy"))
        XCTAssertEqual(taxonomy.categoryTypes.first?.name, "Groceries")
        XCTAssertEqual(taxonomy.categoryTypes.first?.previewImageKeys, ["catalogue/atta-preview.webp"])
        XCTAssertEqual(taxonomy.categoryTypes.first?.navigationSection?.name, "Grocery & Kitchen")
        XCTAssertEqual(taxonomy.categories.first?.categoryTypeID, categoryTypeID)
        XCTAssertEqual(taxonomy.subcategories.first?.categoryID, categoryID)
        XCTAssertEqual(taxonomy.skuPreviews?.first?.imageKey, "catalogue/atta-preview.webp")
        var request = try await requestBody(functions, expectedName: "dastak-v1-catalogue")
        XCTAssertEqual(request["operation"] as? String, "adminSnapshot")
        XCTAssertEqual(request["skuLimit"] as? Int, 1_000)

        let page = try await client.cataloguePage(
            query: "Atta",
            categoryTypeID: categoryTypeID,
            categoryID: categoryID,
            subcategoryID: subcategoryID,
            status: "ACTIVE",
            qaStatus: "VERIFIED",
            limit: 25,
            cursor: nil,
            idempotencyKey: key("admin-catalogue")
        )
        XCTAssertEqual(page.skus.first?.name, "Whole Wheat Atta")
        XCTAssertEqual(page.skus.first?.sellingPricePaise, 7_500)
        XCTAssertEqual(page.skus.first?.activationReady, true)
        XCTAssertEqual(page.skus.first?.activationBlockers, [])
        XCTAssertEqual(page.skus.first?.primaryImage?.rightsStatus, "CLEARED")
        XCTAssertEqual(page.skus.first?.categoryTypeName, "Groceries")
        XCTAssertEqual(page.skus.first?.categoryName, "Flour")
        XCTAssertEqual(page.skus.first?.subcategoryName, "Wheat Flour")
        XCTAssertNil(page.skus.last?.listPricePaise)
        XCTAssertNil(page.skus.last?.sellingPricePaise)
        XCTAssertEqual(page.skus.last?.activationBlockers, ["DASTAK_PRICING_REQUIRED"])
        request = try await requestBody(functions, expectedName: "dastak-v1-catalogue")
        XCTAssertEqual(request["operation"] as? String, "adminCataloguePage")
        XCTAssertEqual(request["categoryTypeId"] as? String, categoryTypeID.uuidString.uppercased())
        XCTAssertEqual(request["categoryId"] as? String, categoryID.uuidString.uppercased())
        XCTAssertEqual(request["subcategoryId"] as? String, subcategoryID.uuidString.uppercased())
        XCTAssertEqual(request["status"] as? String, "ACTIVE")
        XCTAssertEqual(request["qaStatus"] as? String, "VERIFIED")

        let mutation = try await client.updateCatalogueSKU(
            id: skuID,
            expectedVersion: 4,
            listPricePaise: 8_000,
            sellingPricePaise: 7_500,
            status: "ACTIVE",
            idempotencyKey: key("admin-sku-save")
        )
        XCTAssertEqual(mutation.version, 5)
        request = try await requestBody(functions, expectedName: "dastak-v1-catalogue")
        XCTAssertEqual(request["operation"] as? String, "updateSku")
        XCTAssertEqual(request["expectedVersion"] as? Int, 4)
        let patch = try XCTUnwrap(request["patch"] as? [String: Any])
        XCTAssertEqual(patch["listPricePaise"] as? Int, 8_000)
        XCTAssertEqual(patch["sellingPricePaise"] as? Int, 7_500)
        XCTAssertEqual(patch["status"] as? String, "ACTIVE")

        _ = try await client.updateCatalogueSKU(
            id: skuID,
            expectedVersion: 4,
            patch: DastakAdminCatalogueSKUPatch(
                name: "Whole Wheat Atta",
                variant: "Stone ground",
                packSize: "2 x 500 g",
                description: "Whole wheat flour",
                subcategoryID: subcategoryID,
                brandID: nil,
                barcode: "8901234567890",
                quantityValue: 500,
                quantityUnit: "g",
                packCount: 2,
                manufacturerName: "Dastak Foods",
                countryOfOriginCode: "IN",
                hsnCode: "1101",
                dietType: "VEGETARIAN",
                shelfLifeDays: 180,
                listPricePaise: 8_000,
                sellingPricePaise: 7_500,
                taxRateBps: 500,
                qaStatus: "VERIFIED",
                status: "ACTIVE"
            ),
            idempotencyKey: key("admin-sku-rich-save")
        )
        request = try await requestBody(functions, expectedName: "dastak-v1-catalogue")
        let richPatch = try XCTUnwrap(request["patch"] as? [String: Any])
        XCTAssertEqual(richPatch["subcategoryId"] as? String, subcategoryID.uuidString.uppercased())
        XCTAssertEqual(richPatch["quantityValue"] as? Double, 500)
        XCTAssertEqual(richPatch["quantityUnit"] as? String, "g")
        XCTAssertEqual(richPatch["packCount"] as? Int, 2)
        XCTAssertEqual(richPatch["taxRateBps"] as? Int, 500)
        XCTAssertEqual(richPatch["qaStatus"] as? String, "VERIFIED")
    }

    func testGovernanceFinanceAndEvidenceUseProtectedFunctionBoundaries() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)

        let health = try await client.systemHealth(idempotencyKey: key("admin-health"))
        XCTAssertTrue(health.healthy)
        XCTAssertEqual(health.outbox.pending, 1)
        XCTAssertFalse(health.operationalAlerts.breached)
        var request = try await requestBody(functions)
        XCTAssertEqual(request["operation"] as? String, "adminSystemHealth")

        let safety = try await client.operationalSafety(idempotencyKey: key("admin-safety"))
        XCTAssertTrue(safety.permissions.canManageOperationalPauses)
        XCTAssertEqual(safety.pauses.first?.scope, .retailZone)
        XCTAssertEqual(safety.riderEscalations.first?.displayOrderNumber, "DSK-100")

        let payouts = try await client.royaltyPayouts(limit: 25, idempotencyKey: key("admin-payouts"))
        XCTAssertEqual(payouts.first?.amountPaise, 1_800)
        request = try await requestBody(functions, expectedName: "earnings")
        XCTAssertEqual(request["operation"] as? String, "adminRoyaltyPayouts")
        XCTAssertEqual(request["limit"] as? Int, 25)

        let download = try await client.evidenceDownloadURL(
            objectPath: "merchant/33333333-3333-4333-8333-333333333333/evidence.pdf",
            idempotencyKey: key("admin-evidence")
        )
        XCTAssertEqual(download.expiresIn, 300)
        request = try await requestBody(functions, expectedName: "issue-evidence-url")
        XCTAssertEqual(request["bucket"] as? String, "dastak-evidence")
        XCTAssertEqual(request["operation"] as? String, "download")
    }

    func testSafetyMutationsSendOnlyAuditedVersionedInputs() async throws {
        let functions = RecordingAdminFunctionClient()
        let client = SupabaseDastakV1AdminClient(functions: functions)
        let missionID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-8444-444444444444"))

        let escalation = try await client.manageRiderEscalation(
            missionID: missionID,
            action: "RELEASE_REMATCH",
            reason: "Rider is unresponsive before pickup",
            expectedVersion: 4,
            idempotencyKey: key("admin-rematch")
        )
        XCTAssertEqual(escalation.version, 5)
        var request = try await requestBody(functions)
        XCTAssertEqual(request["missionId"] as? String, missionID.uuidString.uppercased())
        XCTAssertEqual(request["action"] as? String, "RELEASE_REMATCH")
        XCTAssertEqual(request["expectedVersion"] as? Int, 4)
        XCTAssertNil(request["accountId"])

        let pause = try await client.setOperationalPause(
            scope: .retailZone,
            targetID: missionID,
            active: true,
            reason: "Weather safety pause",
            expectedVersion: 0,
            idempotencyKey: key("admin-pause")
        )
        XCTAssertTrue(pause.active)
        request = try await requestBody(functions)
        XCTAssertEqual(request["scope"] as? String, "ZONE_RETAIL")
        XCTAssertEqual(request["targetId"] as? String, missionID.uuidString.uppercased())
        XCTAssertEqual(request["active"] as? Bool, true)
        XCTAssertNil(request["accountId"])
    }

    private func key(_ value: String) throws -> IdempotencyKey {
        try XCTUnwrap(IdempotencyKey(rawValue: value))
    }

    private func requestBody(
        _ client: RecordingAdminFunctionClient,
        expectedName: String = "dastak-v1-orders"
    ) async throws -> [String: Any] {
        let recordedCall = await client.lastCall()
        let call = try XCTUnwrap(recordedCall)
        XCTAssertEqual(call.name, expectedName)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: call.body) as? [String: Any])
    }
}

private actor RecordingAdminFunctionClient: FunctionClient {
    struct Call: Sendable { let name: String; let body: Data }
    private var call: Call?

    func invoke<Request, Response>(
        _ name: String,
        request: Request,
        idempotencyKey _: IdempotencyKey
    ) async throws -> Response where Request: Encodable & Sendable, Response: Decodable & Sendable {
        let body = try JSONEncoder().encode(request)
        call = Call(name: name, body: body)
        let operation = try JSONDecoder().decode(AdminOperation.self, from: body).operation
        let response: Data
        switch (name, operation) {
        case ("dastak-v1-orders", "adminExecutionOrders"): response = adminOrdersJSON
        case ("dastak-v1-orders", "adminExecutionTrace"): response = adminTraceJSON
        case ("dastak-v1-orders", "adminAccess"): response = adminAccessJSON
        case ("dastak-v1-orders", "adminCommandCenter"): response = adminCommandCenterJSON
        case ("dastak-v1-orders", "adminNetworkPage"): response = adminNetworkPageJSON
        case ("dastak-v1-orders", "adminSystemHealth"): response = adminSystemHealthJSON
        case ("dastak-v1-orders", "adminOperationalSafety"): response = adminOperationalSafetyJSON
        case ("dastak-v1-orders", "manageRiderEscalation"): response = adminEscalationMutationJSON
        case ("dastak-v1-orders", "setOperationalPause"): response = adminPauseMutationJSON
        case ("dastak-v1-catalogue", "adminCataloguePage"): response = adminCataloguePageJSON
        case ("dastak-v1-catalogue", "adminSnapshot"): response = adminCatalogueTaxonomyJSON
        case ("dastak-v1-catalogue", "updateSku"): response = adminCatalogueMutationJSON
        case ("earnings", "adminRoyaltyPayouts"): response = adminRoyaltyPayoutsJSON
        case ("issue-evidence-url", "download"): response = adminEvidenceJSON
        default: response = executiveSlotJSON
        }
        return try JSONDecoder().decode(Response.self, from: response)
    }

    func lastCall() -> Call? { call }
}

private struct AdminOperation: Decodable { let operation: String }
private let adminOrdersJSON = #"""
{
  "orders":[{
    "id":"77777777-7777-4777-8777-777777777777",
    "displayOrderNumber":"DSK-260903-00000052",
    "orderType":"MARKETPLACE",
    "status":"PREPARING",
    "version":9,
    "paidAt":null,
    "updatedAt":"2026-09-03T16:04:00Z",
    "deliveredAt":null,
    "submittedAt":"2026-09-03T15:59:00Z",
    "fullySecuredAt":"2026-09-03T16:00:00Z"
  }]
}
"""#.data(using: .utf8)!
private let adminTraceJSON = #"""
{
  "order":{
    "id":"77777777-7777-4777-8777-777777777777",
    "displayOrderNumber":"DSK-260903-00000052",
    "orderType":"MARKETPLACE",
    "status":"PREPARING",
    "version":9,
    "paidAt":null,
    "updatedAt":"2026-09-03T16:04:00Z",
    "deliveredAt":null
  },
  "launchPayment":{
    "commitment":{
      "id":"88888888-8888-4888-8888-888888888888",
      "optionCode":"PAY_VIA_UPI_OR_CASH_ON_DELIVERY",
      "customerId":"11111111-1111-4111-8111-111111111111",
      "amountPaise":58500,
      "currencyCode":"INR",
      "securedAt":"2026-09-03T16:00:00Z",
      "reservationExpiresAt":"2026-09-03T16:15:00Z",
      "committedAt":"2026-09-03T16:04:00Z",
      "version":1
    },
    "collectionStatus":"DUE",
    "attempts":[],
    "platformFee":null
  },
  "fulfilments":[],
  "events":[]
}
"""#.data(using: .utf8)!
private let adminAccessJSON = #"""
{
  "role":"SUPERADMIN","canManageAdmins":true,
  "slots":[
    {"slot":0,"role":"SUPERADMIN","email":"super@example.com","linked":true,"version":1},
    {"slot":1,"role":"EXECUTIVE_ADMIN","email":null,"linked":false,"version":1},
    {"slot":2,"role":"EXECUTIVE_ADMIN","email":"future@example.com","linked":false,"version":2}
  ]
}
"""#.data(using: .utf8)!
private let executiveSlotJSON = #"""
{
  "slot":1,"role":"EXECUTIVE_ADMIN","email":"executive@example.com","linked":true,"version":2
}
"""#.data(using: .utf8)!
private let adminCommandCenterJSON = #"""
{
  "observedAt":"2026-08-31T12:34:56Z",
  "actionQueue":{"merchantApplications":2,"deliveryApplications":1,"openIncidents":0,"riderEscalations":1,"activePauses":0},
  "identities":{"activeAccounts":10,"customers":8,"merchants":3,"deliveryPartners":4,"deletedPersonas":1,"recoveryEligiblePhones":1},
  "commerce":{"activeOrders":7,"awaitingPayment":1,"preparingFulfilments":2,"readyFulfilments":1,"activeMissions":3,"deliveredToday":5},
  "network":{"activeOrganizations":3,"activeBranches":4,"onlineRiders":2,"assignedRiders":1},
  "catalogue":{"total":3637,"active":3000,"draft":637,"needsReview":20,"missingPrimaryImage":12}
}
"""#.data(using: .utf8)!
private let adminNetworkPageJSON = #"""
{
  "people":[{
    "id":"33333333-3333-4333-8333-333333333333","displayName":"Furqan",
    "email":"furqan@example.com","phoneNumber":"+919000000000","phoneVerified":true,
    "accountState":"ACTIVE","adminRole":"EXECUTIVE_ADMIN",
    "createdAt":"2026-08-01T10:00:00Z","updatedAt":"2026-08-31T12:00:00Z","lastSignInAt":"2026-08-31T11:00:00Z",
    "personas":[{"persona":"MERCHANT","state":"ACTIVE","activatedAt":"2026-08-02T10:00:00Z","deletedAt":null,"version":1}],
    "customer":{"orderCount":4,"activeOrderCount":1},
    "merchant":{"applicationStatus":"approved","businessName":"Dastak Store","submittedAt":"2026-08-02T10:00:00Z","reviewedAt":"2026-08-03T10:00:00Z","organizationName":"Dastak Store","organizationStatus":"ACTIVE","branchCount":2},
    "delivery":null
  }],
  "hasMore":true,
  "nextCursor":{"updatedAt":"2026-08-31T12:00:00Z","accountId":"33333333-3333-4333-8333-333333333333"}
}
"""#.data(using: .utf8)!
private let adminCatalogueTaxonomyJSON = #"""
{
  "categoryTypes":[{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Groceries","slug":"groceries","imageKey":null,"previewImageKeys":["catalogue/atta-preview.webp"],"navigationSection":{"key":"grocery-kitchen","name":"Grocery & Kitchen","sortOrder":10},"status":"ACTIVE","sortOrder":1,"version":1,"updatedAt":"2026-08-31T12:00:00Z"}],
  "categories":[{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","categoryTypeId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Flour","slug":"flour","imageKey":null,"status":"ACTIVE","sortOrder":1,"version":1,"updatedAt":"2026-08-31T12:00:00Z"}],
  "subcategories":[{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","categoryId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","name":"Wheat Flour","slug":"wheat-flour","imageKey":null,"status":"ACTIVE","sortOrder":1,"version":1,"updatedAt":"2026-08-31T12:00:00Z"}],
  "skus":[{"categoryId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","subcategoryId":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","imageKey":"catalogue/atta-preview.webp"}]
}
"""#.data(using: .utf8)!
private let adminCataloguePageJSON = #"""
{
  "skus":[{
    "id":"22222222-2222-4222-8222-222222222222","categoryTypeId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","categoryTypeName":"Groceries","categoryId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","categoryName":"Flour","subcategoryId":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","subcategoryName":"Wheat Flour","name":"Whole Wheat Atta","brandName":"Dastak","packSize":"1 kg","description":"Stone-ground whole wheat flour.",
    "listPricePaise":8000,"sellingPricePaise":7500,"currencyCode":"INR","status":"ACTIVE","qaStatus":"VERIFIED",
    "activationReady":true,"activationBlockers":[],"imageCount":1,"aliasCount":2,"identifierCount":1,
    "primaryImage":{"id":"88888888-8888-4888-8888-888888888888","imageKey":"catalogue/atta-primary.webp","status":"VERIFIED","rightsStatus":"CLEARED","sourceType":"ADMIN_UPLOAD"},
    "version":4,"updatedAt":"2026-08-31T12:00:00Z"
  },{
    "id":"99999999-9999-4999-8999-999999999999","categoryTypeName":"Groceries","categoryName":"Flour","subcategoryName":"Wheat Flour","name":"Unpriced Draft","brandName":null,"packSize":"1 pack",
    "listPricePaise":null,"sellingPricePaise":null,"currencyCode":"INR","status":"DRAFT","qaStatus":"NEEDS_REVIEW",
    "activationReady":false,"activationBlockers":["DASTAK_PRICING_REQUIRED"],"imageCount":0,"aliasCount":0,"identifierCount":0,
    "primaryImage":null,"version":1,"updatedAt":"2026-08-31T12:00:00Z"
  }],"hasMore":false,"nextCursor":null
}
"""#.data(using: .utf8)!
private let adminCatalogueMutationJSON = #"""
{
  "id":"22222222-2222-4222-8222-222222222222","name":"Whole Wheat Atta",
  "listPricePaise":8000,"sellingPricePaise":7500,"currencyCode":"INR","status":"ACTIVE","version":5,
  "updatedAt":"2026-08-31T12:01:00Z"
}
"""#.data(using: .utf8)!
private let adminSystemHealthJSON = #"""
{
  "healthy":true,"workerConfigured":true,"openCriticalIncidentCount":0,"incidents":[],
  "lastMonitorRun":{"id":"55555555-5555-4555-8555-555555555555","findingCount":0,"startedAt":"2026-08-31T12:00:00Z","completedAt":"2026-08-31T12:00:01Z"},
  "outbox":{"pending":1,"deadLetter":0,"oldestPendingSeconds":2,"staleThresholdSeconds":300},
  "notifications":{"pending":0,"inFlight":1,"deadLetter":0},"paymentReconciliationOpen":0,
  "operationalAlerts":{"breached":false,"counts":{"outboxPendingCount":1,"notificationPendingCount":0,"paymentReconciliationOpenCount":0,"riderEscalationOpenCount":1,"merchantUnreachableBranchCount":0,"customerUnreachableDueCount":0},"thresholds":{"outboxPendingCount":100,"notificationPendingCount":100,"paymentReconciliationOpenCount":5,"riderEscalationOpenCount":10,"merchantUnreachableBranchCount":5,"customerUnreachableDueCount":5}},
  "observedAt":"2026-08-31T12:00:02Z"
}
"""#.data(using: .utf8)!
private let adminOperationalSafetyJSON = #"""
{
  "permissions":{"canManageRiderEscalations":true,"canManageOperationalPauses":true},
  "pauses":[{"id":"66666666-6666-4666-8666-666666666666","scope":"ZONE_RETAIL","targetId":"44444444-4444-4444-8444-444444444444","active":true,"reason":"Weather safety pause","activatedAt":"2026-08-31T12:00:00Z","clearedAt":null,"version":1}],
  "riderEscalations":[{"missionId":"44444444-4444-4444-8444-444444444444","orderId":"77777777-7777-4777-8777-777777777777","displayOrderNumber":"DSK-100","status":"ASSIGNED","riderId":null,"transportType":null,"lastContactAt":null,"lastProgressAt":null,"stallDetectedAt":"2026-08-31T12:00:00Z","unresponsiveDetectedAt":null,"escalationState":"STALLED","escalatedAt":"2026-08-31T12:00:00Z","escalationReason":"No progress","custodyStarted":false,"version":4}]
}
"""#.data(using: .utf8)!
private let adminEscalationMutationJSON = #"""
{"missionId":"44444444-4444-4444-8444-444444444444","status":"MATCHING","escalationState":"NONE","version":5}
"""#.data(using: .utf8)!
private let adminPauseMutationJSON = #"""
{"id":"66666666-6666-4666-8666-666666666666","scope":"ZONE_RETAIL","targetId":"44444444-4444-4444-8444-444444444444","active":true,"reason":"Weather safety pause","version":1,"updatedAt":"2026-08-31T12:00:00Z"}
"""#.data(using: .utf8)!
private let adminRoyaltyPayoutsJSON = #"""
{"withdrawals":[{"id":"88888888-8888-4888-8888-888888888888","subjectType":"RIDER","subjectId":"33333333-3333-4333-8333-333333333333","amountPaise":1800,"effectiveStatus":"REQUESTED","destinationSnapshot":{"type":"UPI","displayLabel":"f***@upi"},"provider":null,"providerPayoutReference":null,"providerStatus":null,"reconciliationState":"PENDING","utr":null,"requestedAt":"2026-08-31T12:00:00Z","attempts":[],"providerRequests":[],"webhookHistory":[]}]}
"""#.data(using: .utf8)!
private let adminEvidenceJSON = #"""
{"signedUrl":"https://storage.example/evidence.pdf?signature=safe","expiresIn":300}
"""#.data(using: .utf8)!
