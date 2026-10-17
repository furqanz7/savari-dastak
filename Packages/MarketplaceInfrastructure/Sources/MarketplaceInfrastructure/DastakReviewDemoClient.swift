import Foundation
import MarketplaceFoundation

/// Release-available, explicitly selected sample environment. There is no URL,
/// credential, transport, production client or network fallback in this actor.
/// Unknown endpoints fail closed. State and idempotency receipts die with it.
public actor DastakReviewDemoClient: FunctionClient {
  public nonisolated static let accountID = UUID(
    uuidString: "de000000-0000-4000-8000-000000000001")!
  private var orders: [[String: Any]] = []
  private var addresses: [[String: Any]] = []
  private var seededAddresses = false
  private var saved: [[String: String]] = []
  private var receipts: [String: Data] = [:]
  private var receiptRequests: [String: Data] = [:]
  private var missionStatus: String?
  private var stopStatus = "PENDING"
  private var pinVerified = false
  private var evidence = false
  private var collected = false
  private var collectionMethod = "CASH"
  private var collectionFailed = false
  private var declined = false
  private var online = true
  private var returnStatus: String?
  private var returnStopStatus = "PENDING"
  private var returnEvidence: [String: Any]?
  private var returnPickupVerified = false
  private var returnCompleted = false
  private var profile = ["displayName": "Alex — Demo", "phoneNumber": "+12025550123"]
  private var missionID: String { orders.first?["id"] as? String ?? Self.id(10) }
  private static let stopID = "de000000-0000-4000-8000-000000000011"
  private static let offerID = "de000000-0000-4000-8000-000000000012"
  private static let addressID = "de000000-0000-4000-8000-000000000013"
  private static var null: Any { NSNull() }
  private static var invalidAction: FunctionClientError {
    .api(
      statusCode: 422, code: "DEMO_INVALID_ACTION",
      message:
        "Complete the current sample step first. Sample PINs are 123456 and the package count is 1."
    )
  }
  private static func id(_ n: Int) -> String { String(format: "de000000-0000-4000-8000-%012d", n) }
  private static func time(_ offset: TimeInterval = 0) -> String {
    ISO8601DateFormatter().string(from: .now.addingTimeInterval(offset))
  }

  public init() {}

  public func customerOrders() throws -> [DastakV1OrderSnapshot] {
    try JSONDecoder().decode(
      [DastakV1OrderSnapshot].self,
      from: JSONSerialization.data(withJSONObject: orders))
  }

  public nonisolated var services: MarketplaceAuthenticatedServices {
    MarketplaceAuthenticatedServices(
      functions: self, isDemonstration: true,
      accountIDProvider: { Self.accountID },
      objectUploader: { _, _, _, _, _ in /* Deliberately discard sample evidence. */ },
      checkoutCustomerProvider: {
        .init(
          displayName: "Alex — Demo", email: "alex@example.invalid", phoneNumber: "+12025550123")
      })
  }

  /// Simulated merchant work is explicit, never a timer pretending to be a live server.
  public func advanceMerchant() {
    guard
      let i = orders.firstIndex(where: {
        ["PREPARING", "PAID"].contains($0["status"] as? String ?? "")
      })
    else { return }
    orders[i]["fulfilmentProgress"] = ["state": "ASSIGNING_RIDER", "title": "Assigning your rider"]
    orders[i]["version"] = (orders[i]["version"] as? Int ?? 1) + 1
    orders[i]["updatedAt"] = Self.time()
  }

  /// Operations assigns a sample return explicitly; never initiates fulfilment.
  public func assignSampleReturn() -> Bool {
    guard let order = orders.first,
      order["status"] as? String == "DELIVERED" || missionStatus == "DELIVERY_RECOVERY"
    else { return false }
    returnStatus = "ASSIGNED"
    returnStopStatus = "PENDING"
    returnEvidence = nil
    returnPickupVerified = false
    returnCompleted = false
    missionStatus = nil
    return true
  }

  public func invoke<Request: Encodable & Sendable, Response: Decodable & Sendable>(
    _ name: String, request: Request, idempotencyKey: IdempotencyKey
  ) async throws -> Response {
    let encoded = try JSONEncoder().encode(request)
    guard var body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
      let op = body["operation"] as? String
    else { throw Self.invalidAction }
    for field in [
      "offerId", "missionId", "stopId", "workId", "addressId", "orderId", "returnMissionId",
      "returnStopId",
    ] {
      if let value = body[field] as? String { body[field] = value.lowercased() }
    }
    let reads: Set<String> = [
      "snapshot", "selfSnapshot", "identitySnapshot", "customerSnapshot", "list", "get",
      "customerCatalogue", "catalogueBrowseMap", "customerRestaurants", "customerAreaAvailability",
      "customerRestaurantAreaPage", "customerCheckoutQuote", "v1PartnerSnapshot", "partnerSnapshot",
      "partnerHistory", "partnerOrderDetail", "deliveryPartnerSnapshot", "deliveryRoyaltySnapshot",
      "v1Heartbeat",
    ]
    let cacheKey = name + ":" + op + ":" + idempotencyKey.rawValue
    let canonicalRequest = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    if !reads.contains(op), let data = receipts[cacheKey] {
      guard receiptRequests[cacheKey] == canonicalRequest else {
        throw FunctionClientError.api(
          statusCode: 409, code: "DEMO_IDEMPOTENCY_CONFLICT",
          message: "The saved sample action has different details. Refresh before trying again.")
      }
      return try JSONDecoder().decode(Response.self, from: data)
    }
    let result = try response(name, op, body)
    let data = try JSONSerialization.data(
      withJSONObject: result, options: [.fragmentsAllowed, .sortedKeys])
    // Decode before saving a receipt, so malformed sample contracts fail visibly.
    let value = try JSONDecoder().decode(Response.self, from: data)
    if !reads.contains(op) {
      receipts[cacheKey] = data
      receiptRequests[cacheKey] = canonicalRequest
    }
    return value
  }

  private func response(_ name: String, _ op: String, _ body: [String: Any]) throws -> Any {
    switch (name, op) {
    case ("dastak-v1-catalogue", "customerCatalogue"):
      var value = Self.catalogue
      var items = Self.products
      if let id = body["categoryId"] as? String {
        items = items.filter { $0["categoryId"] as? String == id.lowercased() }
      }
      if let id = body["subcategoryId"] as? String {
        items = items.filter { $0["subcategoryId"] as? String == id.lowercased() }
      }
      if let query = body["query"] as? String, !query.isEmpty {
        items = items.filter {
          ($0["name"] as? String ?? "").localizedCaseInsensitiveContains(query)
        }
      }
      value["skus"] = items
      return value
    case ("dastak-v1-catalogue", "catalogueBrowseMap"):
      let source: [String: Any] = [
        "typeSlug": "grocery", "categorySlug": "pantry", "excludedCategorySlugs": [],
        "excludedSubcategorySlugs": [],
      ]
      return [
        "version": 1,
        "nodes": [
          [
            "key": "demo-grocery", "kind": "SECTION", "label": "Grocery", "sortOrder": 0,
            "sources": [],
          ],
          [
            "key": "demo-pantry", "parentKey": "demo-grocery", "kind": "DESTINATION",
            "label": "Pantry essentials", "sortOrder": 0, "sources": [source],
          ],
          [
            "key": "demo-rice", "parentKey": "demo-pantry", "kind": "RAIL",
            "label": "Rice, coffee & dals", "sortOrder": 0, "sources": [source],
          ],
        ],
      ]
    case ("dastak-v1-catalogue", "customerRestaurants"):
      return ["restaurants": Self.restaurants]
    case ("dastak-v1-catalogue", "customerRestaurantAreaPage"):
      return [
        "restaurants": Self.restaurants, "nextCursor": Self.null, "ordering": "NEAREST",
        "addressId": body["addressId"] ?? Self.addressID,
        "addressVersion": body["addressVersion"] ?? Self.time(),
      ]
    case ("dastak-v1-catalogue", "customerAreaAvailability"):
      return [
        "addressId": body["addressId"] ?? Self.addressID,
        "addressVersion": body["addressVersion"] ?? Self.time(), "checkedAt": Self.time(),
        "groceryServiceable": true, "foodServiceable": true, "deliveryAvailable": true,
        "stock": Dictionary(
          uniqueKeysWithValues: Self.products.dropLast().map { ($0["id"] as! String, 20) }),
        "restaurants": [Self.id(101): true], "trendingSkus": Array(Self.products.prefix(3)),
      ]
    case ("dastak-v1-catalogue", "customerCheckoutQuote"):
      let lines = try pricedLines(body["lines"] as? [[String: Any]] ?? [])
      var quote = price(lines)
      quote.merge([
        "addressId": body["addressId"] ?? Self.addressID,
        "addressVersion": body["addressVersion"] ?? Self.time(), "lines": body["lines"] ?? [],
        "restaurantBranchId": body["restaurantBranchId"] ?? Self.null, "kind": "ESTIMATE",
        "pricingVersion": 1, "checkedAt": Self.time(), "validUntil": Self.time(30),
        "deliveryDistanceMeters": 700, "deliveryAvailable": true,
      ]) { _, new in new }
      return quote
    case ("customer-addresses", _): return try addressResponse(op, body)
    case ("account-profile", "snapshot"), ("account-profile", "update"):
      if let name = body["displayName"] as? String { profile["displayName"] = name }
      if let phone = body["phoneNumber"] as? String { profile["phoneNumber"] = phone }
      return ["profile": profile]
    case ("account-profile", "identitySnapshot"): return ["providers": []]
    case ("account-profile", "export"):
      return [
        "filename": "dastak-demo-export.json",
        "export": [
          "environment": "DEMO", "profile": profile, "orders": orders, "addresses": addresses,
        ],
      ]
    case ("account-sessions", "snapshot"), ("account-sessions", "signOutOthers"):
      return ["sessions": []]
    case ("customer-wishlist", "snapshot"): return ["items": saved]
    case ("customer-wishlist", "set"):
      guard let kind = body["itemKind"] as? String, let id = body["itemId"] as? String else {
        throw Self.invalidAction
      }
      saved.removeAll { $0["itemId"]?.lowercased() == id.lowercased() && $0["kind"] == kind }
      if body["wished"] as? Bool == true {
        saved.append(["kind": kind, "itemId": id, "createdAt": Self.time()])
      }
      return ["items": saved]
    case ("dastak-v1-orders", _): return try orderResponse(op, body)
    case ("delivery-partners", "selfSnapshot"), ("delivery-partners", "setAvailability"),
      ("delivery-partners", "publishLocation"):
      if let value = body["online"] as? Bool { online = value }
      return [
        "onboardingState": "approved", "deliveryMethod": "scooter",
        "availability": [
          "status": online ? "online" : "offline",
          "location": ["latitude": 12.6819, "longitude": 78.6201],
          "availableUntil": Self.time(3600), "stateVersion": 1,
        ],
      ]
    case ("courier-dispatch", "partnerSnapshot"):
      return ["offer": Self.null, "currentJob": Self.null]
    case ("parcel-deliveries", "partnerSnapshot"):
      return ["offer": Self.null, "currentJob": Self.null]
    case ("merchant-orders", "customerSnapshot"): return ["orders": []]
    case ("parcel-deliveries", "customerSnapshot"): return []
    case ("courier-dispatch", "v1PartnerSnapshot"): return dispatch()
    case ("courier-dispatch", "partnerHistory"): return ["items": history()]
    case ("courier-dispatch", "partnerOrderDetail"): return try detail(body)
    case ("courier-dispatch", "v1Heartbeat"):
      return [
        "missionId": missionID, "version": version, "lastContactAt": Self.time(),
        "escalationState": "NONE",
      ]
    case ("courier-dispatch", _): return try deliveryAction(op, body)
    case ("earnings", "deliveryPartnerSnapshot"):
      return [
        "currency": "INR", "completedPaise": history().count * 2500, "pendingPaise": 0,
        "thisWeekPaise": history().count * 2500,
      ]
    case ("earnings", "deliveryRoyaltySnapshot"):
      return [
        "currency": "INR", "balancePaise": 0, "availablePaise": 0, "negativeBalancePaise": 0,
        "lifetimeEarnedPaise": history().count * 2500,
        "payoutAvailability": [
          "destinationRegistrationAvailable": false, "withdrawalExecutionAvailable": false,
        ], "subjects": [],
      ]
    default:
      throw FunctionClientError.api(
        statusCode: 403, code: "DEMO_ISOLATED",
        message: "This action is unavailable in the isolated demo. No live request was sent.")
    }
  }

  private func addressResponse(_ op: String, _ body: [String: Any]) throws -> Any {
    if !seededAddresses {
      addresses = [Self.sampleAddress]
      seededAddresses = true
    }
    let id = (body["addressId"] as? String)?.lowercased() ?? UUID().uuidString.lowercased()
    switch op {
    case "snapshot": break
    case "save", "saveDefault":
      var item = Self.sampleAddress
      item["addressId"] = id
      for key in ["label", "address", "building", "floor", "landmark", "deliveryNotes", "location"]
      { if let value = body[key] { item[key] = value } }
      item["details"] = body["building"] ?? body["details"] ?? "Sample doorstep"
      item["displayAddress"] = item["address"]
      item["updatedAt"] = Self.time()
      item["isDefault"] =
        body["makeDefault"] as? Bool == true || op == "saveDefault" || addresses.isEmpty
        || addresses.contains {
          $0["addressId"] as? String == id && $0["isDefault"] as? Bool == true
        }
      addresses.removeAll { $0["addressId"] as? String == id }
      if item["isDefault"] as? Bool == true {
        for i in addresses.indices { addresses[i]["isDefault"] = false }
      }
      addresses.append(item)
    case "setDefault":
      for i in addresses.indices {
        addresses[i]["isDefault"] = addresses[i]["addressId"] as? String == id
      }
    case "delete":
      addresses.removeAll { $0["addressId"] as? String == id }
      if !addresses.isEmpty && !addresses.contains(where: { $0["isDefault"] as? Bool == true }) {
        addresses[0]["isDefault"] = true
      }
    default: throw Self.invalidAction
    }
    return ["addresses": addresses]
  }

  private func pricedLines(_ input: [[String: Any]]) throws -> [[String: Any]] {
    guard !input.isEmpty, input.count <= 100 else { throw Self.invalidAction }
    return try input.map { line in
      let sku = line["skuId"] as? String
      let id = (sku ?? line["menuItemId"] as? String ?? "").lowercased()
      let items = Self.products + Self.menuItems
      guard let product = items.first(where: { $0["id"] as? String == id }), id != Self.id(24),
        let quantity = line["quantity"] as? Int, (1...20).contains(quantity)
      else { throw Self.invalidAction }
      let unit = product["sellingPricePaise"] as? Int ?? product["basePricePaise"] as? Int ?? 0
      var result: [String: Any] = [
        "id": UUID().uuidString, "lineType": sku == nil ? "FOOD_MENU_ITEM" : "RETAIL_SKU",
        "name": product["name"] ?? "Sample item", "quantity": quantity, "unitPricePaise": unit,
        "lineTotalPaise": unit * quantity, "status": "SECURED",
      ]
      result[sku == nil ? "menuItemId" : "skuId"] = id
      result["packSize"] = product["packSize"]
      return result
    }
  }
  private func price(_ lines: [[String: Any]]) -> [String: Any] {
    let subtotal = lines.reduce(0) { $0 + ($1["lineTotalPaise"] as? Int ?? 0) }
    let fee = ((subtotal + 1500) * 200 + 5000) / 10000
    return [
      "snapshotKind": "FINAL", "subtotalPaise": subtotal, "deliveryFeePaise": 1500,
      "platformFeePaise": fee, "discountPaise": 0, "taxPaise": 0,
      "totalPaise": subtotal + 1500 + fee, "currencyCode": "INR",
    ]
  }
  private var version: Int { orders.first?["version"] as? Int ?? 1 }
  private func orderResponse(_ op: String, _ body: [String: Any]) throws -> Any {
    if op == "list" { return ["orders": orders, "nextCursor": Self.null] }
    if op == "submit" {
      guard
        orders.allSatisfy({
          ["DELIVERED", "CANCELLED", "CANCELLED_PREPAYMENT"].contains($0["status"] as? String ?? "")
        }),
        let submission = body["order"] as? [String: Any]
      else { throw Self.invalidAction }
      let lines = try pricedLines(submission["lines"] as? [[String: Any]] ?? [])
      var order: [String: Any] = [
        "id": UUID().uuidString.lowercased(), "displayOrderNumber": "DEMO-\(orders.count + 1)",
        "orderType": submission["restaurantBranchId"] == nil ? "RETAIL_ONLY" : "FOOD_ONLY",
        "status": "AWAITING_PAYMENT", "version": 1, "createdAt": Self.time(),
        "updatedAt": Self.time(), "fullySecuredAt": Self.time(), "paymentExpiresAt": Self.time(300),
        "price": price(lines), "lines": lines,
        "deliveryAddress": submission["deliveryAddress"] ?? Self.sampleAddress,
        "recipient": ["name": "Alex — Demo", "phoneNumber": "+12025550123"],
      ]
      order["launchPayment"] = launchPayment(
        confirmed: false, amount: price(lines)["totalPaise"] as! Int)
      order["support"] = [
        "canReportIssue": false, "recovery": [], "issues": [], "returns": [], "refunds": [],
      ]
      if submission["restaurantBranchId"] != nil {
        order["restaurant"] = Self.restaurants[0]["restaurant"]
      }
      orders.insert(order, at: 0)
      missionStatus = nil
      stopStatus = "PENDING"
      pinVerified = false
      evidence = false
      collected = false
      collectionFailed = false
      declined = false
      returnStatus = nil
      returnCompleted = false
      return order
    }
    guard let id = body["orderId"] as? String,
      let i = orders.firstIndex(where: { ($0["id"] as? String)?.lowercased() == id.lowercased() })
    else { throw Self.invalidAction }
    if op == "get" { return orders[i] }
    if op == "reportCustomerIssue" {
      guard orders[i]["status"] as? String == "DELIVERED",
        let category = body["category"] as? String,
        let description = body["description"] as? String, description.count >= 3
      else { throw Self.invalidAction }
      let issueID = UUID().uuidString
      let timestamp = Self.time()
      var support = orders[i]["support"] as? [String: Any] ?? [:]
      var issues = support["issues"] as? [[String: Any]] ?? []
      issues.append([
        "id": issueID, "category": category, "status": "OPEN", "description": description,
        "reportedAt": timestamp, "version": 1, "evidence": [],
      ])
      support["issues"] = issues
      orders[i]["support"] = support
      return [
        "issueId": issueID, "orderId": id, "category": category, "status": "OPEN",
        "reportedAt": timestamp,
      ]
    }
    guard body["expectedVersion"] as? Int == orders[i]["version"] as? Int else {
      throw FunctionClientError.api(
        statusCode: 409, code: "STALE_VERSION", message: "Refresh the demo order and try again.")
    }
    switch op {
    case "commitLaunchPayment":
      guard orders[i]["status"] as? String == "AWAITING_PAYMENT" else { throw Self.invalidAction }
      orders[i]["status"] = "PREPARING"
      orders[i]["paidAt"] = Self.time()
      orders[i]["fulfilmentProgress"] = ["state": "PREPARING", "title": "Preparing your order"]
      orders[i]["launchPayment"] = launchPayment(
        confirmed: true, amount: (orders[i]["price"] as! [String: Any])["totalPaise"] as! Int)
    case "cancel":
      guard missionStatus == nil || missionStatus == "ASSIGNED" else { throw Self.invalidAction }
      orders[i]["status"] = "CANCELLED"
      missionStatus = nil
    default: throw Self.invalidAction
    }
    orders[i]["version"] = (orders[i]["version"] as! Int) + 1
    orders[i]["updatedAt"] = Self.time()
    return orders[i]
  }
  private func launchPayment(confirmed: Bool, amount: Int) -> [String: Any] {
    [
      "optionLabel": "Pay via UPI/Cash on Delivery",
      "state": collected
        ? "PAYMENT_COLLECTED" : confirmed ? "PAYMENT_DUE_AT_DELIVERY" : "READY_TO_CONFIRM",
      "amountPaise": amount, "currencyCode": "INR", "securedAt": Self.time(),
      "reservationExpiresAt": Self.time(300), "reservationSecondsRemaining": confirmed ? 0 : 300,
      "reservationState": confirmed ? "COMMITTED" : "ACTIVE", "canCommit": !confirmed,
      "noChargeNow": true, "payAtDoorstep": true,
    ]
  }

  private func dispatch() -> [String: Any] {
    var result: [String: Any] = [
      "offer": Self.null, "currentMission": Self.null, "returnMission": Self.null,
      "completedMission": Self.null,
    ]
    guard let order = orders.first else { return result }
    if let returnStatus {
      result["returnMission"] = returnMission(order, status: returnStatus)
      return result
    }
    let status = order["status"] as? String ?? ""
    if status == "DELIVERED" {
      result["completedMission"] = [
        "id": missionID, "orderId": order["id"]!, "verificationStatus": "CONSUMED",
        "status": "DELIVERED", "deliveredAt": order["deliveredAt"]!, "packageCount": 1,
      ]
    } else if let missionStatus {
      result["currentMission"] = mission(order, status: missionStatus)
    } else if status == "PREPARING",
      (order["fulfilmentProgress"] as? [String: Any])?["state"] as? String == "ASSIGNING_RIDER",
      !declined, online
    {
      result["offer"] = [
        "id": Self.offerID, "missionId": missionID,
        "displayOrderNumber": order["displayOrderNumber"]!, "transportType": "SCOOTER",
        "distanceMeters": 700, "respondBy": Self.time(3600), "secondsRemaining": 3600,
        "pickupCount": 1,
        "orderLoad": [
          "totalWeightGrams": 1000, "totalVolumeCubicMillimetres": 1_000_000,
          "longestSideMillimetres": 200, "containsBulky": false,
          "eligibleTransportTypes": ["SCOOTER"],
        ], "pickupStops": [stop()],
      ]
    }
    return result
  }
  private func stop() -> [String: Any] {
    [
      "id": Self.stopID, "sequence": 1, "status": stopStatus, "ready": true, "runningLate": false,
      "packageCount": 1, "waitingSeconds": 0,
      "branch": [
        "id": Self.id(101), "displayName": "Sample Dastak pickup", "address": Self.destination,
      ], "arrival": eligibility,
    ]
  }
  private var eligibility: [String: Any] {
    [
      "eligible": true, "reason": "DEMO_SAMPLE_LOCATION", "distanceMeters": 0, "radiusMeters": 100,
      "validUntil": Self.time(3600),
    ]
  }
  private func collection(_ order: [String: Any]) -> [String: Any] {
    [
      "required": true,
      "state": collected
        ? "PAYMENT_COLLECTED"
        : collectionFailed ? "COLLECTION_RETRY_NEEDED" : "PAYMENT_DUE_AT_DELIVERY",
      "amountPaise": (order["price"] as! [String: Any])["totalPaise"]!, "currencyCode": "INR",
      "methods": ["CASH", "UPI"], "canRecord": missionStatus == "ARRIVED" && !collected,
      "lastOutcome": collected ? "COLLECTED" : collectionFailed ? "FAILED" : Self.null,
      "lastMethod": collected || collectionFailed ? collectionMethod : Self.null,
    ]
  }
  private func mission(_ order: [String: Any], status: String) -> [String: Any] {
    [
      "id": missionID, "displayOrderNumber": order["displayOrderNumber"]!, "status": status,
      "version": version, "pickupCount": 1, "pickupStops": [stop()],
      "customerDestination": [
        "address": Self.destination, "recipient": ["name": "Alex — Demo", "phoneNumber": ""],
      ],
      "finalVerification": [
        "status": "ACTIVE", "failedAttempts": 0, "evidencePresent": evidence,
        "pinVerified": pinVerified,
      ], "launchCollection": collection(order),
      "canStartFinalDelivery": status == "ALL_PACKAGES_PICKED_UP",
      "canArriveCustomer": status == "OUT_FOR_DELIVERY",
      "canCaptureDeliveryEvidence": status == "ARRIVED", "canVerifyDelivery": false,
      "canVerifyCustomerPIN": status == "ARRIVED" && !pinVerified,
      "canCompleteDelivery": status == "ARRIVED" && pinVerified && evidence && collected,
      "canCancelBeforePickup": stopStatus != "COMPLETED",
      "mustUseDeliveryRecovery": stopStatus == "COMPLETED", "customerArrival": eligibility,
    ]
  }
  private func deliveryAction(_ op: String, _ body: [String: Any]) throws -> Any {
    guard !orders.isEmpty else { throw Self.invalidAction }
    if op.hasPrefix("v1Return")
      || [
        "v1AddReturnEvidence", "v1VerifyReturnPickup", "v1ArriveAtReturnStop",
        "v1VerifyReturnReceipt",
      ].contains(op)
    {
      return try returnAction(op, body)
    }
    let status = missionStatus
    if let expected = (body["expectedVersion"] ?? body["expectedMissionVersion"]) as? Int,
      expected != version
    {
      throw FunctionClientError.api(
        statusCode: 409, code: "STALE_VERSION", message: "Refresh the sample mission.")
    }
    switch op {
    case "v1AcceptOffer":
      guard body["offerId"] as? String == Self.offerID, dispatch()["offer"] is [String: Any] else {
        throw Self.invalidAction
      }
      missionStatus = "ASSIGNED"
    case "v1DeclineOffer":
      declined = true
      return dispatch()
    case "v1StartPickups":
      guard status == "ASSIGNED" else { throw Self.invalidAction }
      missionStatus = "EN_ROUTE_TO_PICKUPS"
      orders[0]["status"] = "PICKUP_IN_PROGRESS"
    case "v1ArriveAtPickup":
      guard status == "EN_ROUTE_TO_PICKUPS", body["stopId"] as? String == Self.stopID else {
        throw Self.invalidAction
      }
      stopStatus = "ARRIVED"
      missionStatus = "PICKUP_IN_PROGRESS"
    case "v1VerifyPickup":
      guard status == "PICKUP_IN_PROGRESS", body["verificationCode"] as? String == "123456",
        (body["accountedPackageCount"] ?? body["packageCount"]) as? Int == 1
      else { throw Self.invalidAction }
      stopStatus = "COMPLETED"
      missionStatus = "ALL_PACKAGES_PICKED_UP"
    case "v1StartFinalDelivery":
      guard status == "ALL_PACKAGES_PICKED_UP" else { throw Self.invalidAction }
      missionStatus = "OUT_FOR_DELIVERY"
      orders[0]["status"] = "OUT_FOR_DELIVERY"
    case "v1ArriveAtCustomer":
      guard status == "OUT_FOR_DELIVERY" else { throw Self.invalidAction }
      missionStatus = "ARRIVED"
    case "v1VerifyCustomerPIN":
      guard status == "ARRIVED", body["verificationCode"] as? String == "123456" else {
        throw Self.invalidAction
      }
      pinVerified = true
    case "v1AddDeliveryEvidence":
      guard status == "ARRIVED", body["objectPath"] as? String != nil else {
        throw Self.invalidAction
      }
      evidence = true
    case "v1RecordLaunchCollection":
      guard status == "ARRIVED", ["CASH", "UPI"].contains(body["method"] as? String ?? "") else {
        throw Self.invalidAction
      }
      collectionMethod = body["method"] as? String ?? "CASH"
      collected = body["outcome"] as? String == "COLLECTED"
      collectionFailed = !collected
    case "v1CompleteDelivery":
      guard status == "ARRIVED", pinVerified, evidence, collected else { throw Self.invalidAction }
      orders[0]["status"] = "DELIVERED"
      orders[0]["deliveredAt"] = Self.time()
      missionStatus = nil
    case "v1CancelBeforePickup":
      guard stopStatus != "COMPLETED" else { throw Self.invalidAction }
      missionStatus = nil
      declined = true
    case "v1ReportDeliveryProblem", "v1ReportCustomerUnreachable":
      guard stopStatus == "COMPLETED", (body["reason"] as? String ?? "").count >= 3 else {
        throw Self.invalidAction
      }
      missionStatus = "DELIVERY_RECOVERY"
    default:
      throw FunctionClientError.api(
        statusCode: 403, code: "DEMO_ISOLATED",
        message: "This sample scenario does not support that action. No live request was sent.")
    }
    orders[0]["version"] = version + 1
    orders[0]["updatedAt"] = Self.time()
    if op == "v1RecordLaunchCollection" || op == "v1CompleteDelivery" {
      orders[0]["launchPayment"] = launchPayment(
        confirmed: true, amount: (orders[0]["price"] as! [String: Any])["totalPaise"] as! Int)
    }
    if op == "v1CompleteDelivery" {
      orders[0]["support"] = [
        "canReportIssue": true, "recovery": [], "issues": [], "returns": [], "refunds": [],
      ]
      orders[0].removeValue(forKey: "tracking")
      orders[0]["delivery"] = [
        "state": "DELIVERED", "verificationStatus": "CONSUMED", "deliveredAt": Self.time(),
        "recipientAccountRequired": false, "pinVerified": true,
      ]
    }
    if let missionStatus {
      orders[0]["tracking"] = [
        "missionId": missionID, "phase": missionStatus, "riderName": "Sam — Demo",
        "transportType": "SCOOTER", "serverTime": Self.time(),
      ]
      if missionStatus == "ARRIVED" {
        orders[0]["delivery"] = [
          "state": "ARRIVED", "verificationStatus": "ACTIVE", "deliveryCode": "123456",
          "riderArrivedAt": Self.time(), "recipientAccountRequired": false,
        ]
      }
    }
    return dispatch()
  }
  private func history() -> [[String: Any]] {
    var records: [[String: Any]] = orders.filter { $0["status"] as? String == "DELIVERED" }.map {
      [
        "kind": "V1_DELIVERY", "workId": $0["id"]!, "reference": $0["displayOrderNumber"]!,
        "status": "DELIVERED", "startedAt": $0["createdAt"]!, "endedAt": $0["deliveredAt"]!,
        "packageCount": 1, "payoutPaise": 2500, "outcome": "COMPLETED",
      ]
    }
    if returnCompleted, let order = orders.first {
      records.insert(
        [
          "kind": "RETURN", "workId": Self.id(200), "reference": order["displayOrderNumber"]!,
          "status": "COMPLETED", "startedAt": order["createdAt"]!, "endedAt": Self.time(),
          "packageCount": 1, "payoutPaise": 0, "outcome": "RETURNED",
        ], at: 0)
    }
    return records
  }
  private func detail(_ body: [String: Any]) throws -> Any {
    guard let workID = body["workId"] as? String,
      var order = workID == Self.id(200)
        ? orders.first : orders.first(where: { $0["id"] as? String == workID })
    else { throw Self.invalidAction }
    let terminal = order["status"] as? String == "DELIVERED"
    if terminal {
      order.removeValue(forKey: "deliveryAddress")
      order.removeValue(forKey: "recipient")
    }
    return [
      "kind": body["kind"] ?? "V1_DELIVERY", "workId": workID,
      "missionStatus": workID == Self.id(200)
        ? returnStatus ?? "COMPLETED" : terminal ? "DELIVERED" : missionStatus ?? "ASSIGNED",
      "terminal": terminal, "order": order, "pickupStops": [stop()],
      "collection": collection(order),
    ]
  }

  private func returnMission(_ order: [String: Any], status: String) -> [String: Any] {
    [
      "id": Self.id(200), "returnId": Self.id(201), "orderId": order["id"]!, "status": status,
      "version": version, "transportType": "SCOOTER", "assignedAt": Self.time(),
      "arrivedCustomerAt": status == "ASSIGNED" ? Self.null : Self.time(),
      "pickupCompletedAt": returnPickupVerified ? Self.time() : Self.null,
      "customerDestination": ["address": Self.destination], "packageCount": 1,
      "pickupVerification": [
        "status": returnPickupVerified ? "CONSUMED" : "ACTIVE", "failedAttempts": 0,
      ], "evidence": returnEvidence.map { [$0] } ?? [],
      "stops": [
        [
          "id": Self.id(202), "sequence": 1, "status": returnStopStatus, "packageCount": 1,
          "arrivedAt": returnStopStatus == "PENDING" ? Self.null : Self.time(),
          "verificationStatus": returnStopStatus == "COMPLETED" ? "CONSUMED" : "ACTIVE",
          "failedAttempts": 0, "arrival": eligibility, "canArrive": returnPickupVerified,
          "branch": [
            "id": Self.id(101), "displayName": "Sample Dastak pickup", "address": Self.destination,
            "location": ["latitude": 12.6819, "longitude": 78.6201],
          ],
        ]
      ], "customerArrival": eligibility, "canArriveCustomer": status == "ASSIGNED",
      "canCaptureEvidence": status == "AT_CUSTOMER", "canVerifyPickup": status == "AT_CUSTOMER",
      "canCompleteReturnStops": returnPickupVerified,
    ]
  }
  private func returnAction(_ op: String, _ body: [String: Any]) throws -> Any {
    guard let status = returnStatus, body["returnMissionId"] as? String == Self.id(200) else {
      throw Self.invalidAction
    }
    switch op {
    case "v1ReturnArriveAtCustomer":
      guard status == "ASSIGNED" else { throw Self.invalidAction }
      returnStatus = "AT_CUSTOMER"
    case "v1AddReturnEvidence":
      guard status == "AT_CUSTOMER", let path = body["objectPath"] as? String else {
        throw Self.invalidAction
      }
      returnEvidence = [
        "id": Self.id(203), "objectPath": path, "contentType": "image/jpeg",
        "capturedAt": Self.time(),
      ]
    case "v1VerifyReturnPickup":
      guard status == "AT_CUSTOMER", returnEvidence != nil,
        body["verificationCode"] as? String == "123456"
      else { throw Self.invalidAction }
      returnPickupVerified = true
      returnStatus = "RETURNING_TO_MERCHANTS"
    case "v1ArriveAtReturnStop":
      guard status == "RETURNING_TO_MERCHANTS", returnStopStatus == "PENDING",
        body["returnStopId"] as? String == Self.id(202)
      else { throw Self.invalidAction }
      returnStopStatus = "ARRIVED"
    case "v1VerifyReturnReceipt":
      guard returnStopStatus == "ARRIVED", body["verificationCode"] as? String == "123456" else {
        throw Self.invalidAction
      }
      returnStopStatus = "COMPLETED"
      returnStatus = nil
      returnCompleted = true
    default: throw Self.invalidAction
    }
    orders[0]["version"] = version + 1
    return dispatch()
  }

  private static var destination: [String: Any] {
    [
      "label": "Demo Home", "line1": "24, Sample Garden Street", "city": "Vaniyambadi",
      "state": "Tamil Nadu", "postalCode": "635751", "countryCode": "IN", "latitude": 12.6819,
      "longitude": 78.6201,
    ]
  }
  private static var sampleAddress: [String: Any] {
    [
      "addressId": addressID, "label": "Home", "address": "Sample Garden Street, Vaniyambadi",
      "building": "24", "details": "24 • Sample doorstep",
      "displayAddress": "24, Sample Garden Street, Vaniyambadi",
      "location": ["latitude": 12.6819, "longitude": 78.6201], "isDefault": true,
      "updatedAt": time(),
    ]
  }
  private static var products: [[String: Any]] {
    [
      (20, "Basmati rice", "1 kg", 14900, "rice"), (21, "Basmati rice", "5 kg", 69900, "rice"),
      (22, "Classic coffee", "100 g", 19900, "coffee"), (23, "Toor dal", "1 kg", 16900, "dal"),
      (24, "Toor dal", "500 g", 8900, "dal"),
    ].map { n, name, pack, amount, image in
      [
        "id": id(n), "categoryTypeId": id(2), "categoryId": id(3),
        "subcategoryId": id(image == "rice" ? 4 : image == "coffee" ? 5 : 6),
        "brand": ["id": id(7), "name": "Sample Pantry", "slug": "sample-pantry"], "name": name,
        "slug": "sample-\(image)", "packSize": pack,
        "description": "Sample product for exploring Dastak. No real purchase.",
        "imageKey": "review-demo/\(image).png", "listPricePaise": amount,
        "sellingPricePaise": amount, "currencyCode": "INR", "logisticsAttributes": [:],
      ]
    }
  }
  private static var catalogue: [String: Any] {
    [
      "catalogueVersion": "DEMO-1",
      "categoryTypes": [["id": id(2), "name": "Grocery", "slug": "grocery", "sortOrder": 0]],
      "categories": [
        [
          "id": id(3), "categoryTypeId": id(2), "name": "Pantry essentials", "slug": "pantry",
          "sortOrder": 0,
        ]
      ],
      "subcategories": [(4, "Rice", "rice"), (5, "Coffee", "coffee"), (6, "Dals & pulses", "dal")]
        .map { n, name, slug in
          [
            "id": id(n), "categoryId": id(3), "name": name, "slug": slug, "sortOrder": n,
            "imageKey": "review-demo/\(slug).png",
          ]
        }, "skus": products, "nextCursor": null,
    ]
  }
  private static var menuItems: [[String: Any]] {
    [
      (103, "Classic burger", 18900, "burger"), (104, "Golden fries", 9900, "fries"),
      (105, "Cappuccino", 12500, "coffee"),
    ].map { n, name, amount, image in
      [
        "id": id(n), "name": name, "description": "Prepared for the sample menu.",
        "basePricePaise": amount, "currencyCode": "INR", "taxRateBps": 0, "status": "ACTIVE",
        "sortOrder": n, "version": 1, "logisticsAttributes": [:], "optionGroups": [],
        "imageKey": "review-demo/\(image).png",
      ]
    }
  }
  private static var restaurants: [[String: Any]] {
    [
      [
        "restaurant": [
          "organizationId": id(100), "branchId": id(101), "name": "The Sample Garden Kitchen",
          "branchName": "The Sample Garden Kitchen",
          "description": "Sample burgers, sides and coffee", "imageKey": "review-demo/burger.png",
          "acceptingOrders": true, "isOpen": true, "branchStatus": "ACTIVE",
          "merchantType": "RESTAURANT", "softActiveOrderThreshold": 10, "activeOrderCount": 0,
        ],
        "categories": [("Burgers", 0), ("Sides", 1), ("Hot drinks", 2)].map { name, i in
          [
            "id": id(110 + i), "name": name, "sortOrder": i, "status": "ACTIVE", "version": 1,
            "items": [menuItems[i]],
          ]
        },
      ]
    ]
  }
}
