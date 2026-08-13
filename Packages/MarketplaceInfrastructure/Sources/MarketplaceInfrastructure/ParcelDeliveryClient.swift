import Foundation
import MarketplaceFoundation

public struct AddressedGeoPoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let address: String

    public init(latitude: Double, longitude: Double, address: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
    }
}

public enum ParcelDeliveryStatus: String, Codable, Equatable, Sendable {
    case paymentPending = "payment_pending"
    case paid
    case assigned
    case enRouteToPickup = "en_route_to_pickup"
    case pickedUp = "picked_up"
    case inTransit = "in_transit"
    case delivered
    case cancelled
}

public enum ParcelPaymentStatus: String, Codable, Equatable, Sendable {
    case pending
    case paid
    case failed
    case refundPending = "refund_pending"
    case refunded
    case cancelled
}

public enum ParcelRefundStatus: String, Codable, Equatable, Sendable {
    case notRequested = "not_requested"
    case pending
    case completed
    case notEligible = "not_eligible"
}

public enum ParcelHandoffPurpose: String, Codable, Equatable, Sendable {
    case pickup
    case delivery
}

public enum ParcelAssignmentStatus: String, Codable, Equatable, Sendable {
    case offered
    case acknowledged
}

public enum ParcelDeliveryAudience: String, Codable, Equatable, Sendable {
    case sender
    case recipient
}

public struct ParcelQuote: Codable, Equatable, Sendable {
    public let quoteID: UUID
    public let deliveryMethod: DeliveryMethod
    public let routeDistanceMeters: Int
    public let routeDurationSeconds: Int
    public let deliveryFee: Money
    public let courierPayout: Money
    public let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case quoteID = "quoteId"
        case deliveryMethod
        case routeDistanceMeters
        case routeDurationSeconds
        case deliveryFee
        case courierPayout
        case expiresAt
    }
}

public struct ParcelRecipient: Codable, Equatable, Sendable {
    public let name: String
    public let phoneNumber: String
}

public struct ParcelHandoffCode: Codable, Equatable, Sendable {
    public let purpose: ParcelHandoffPurpose
    public let code: String
    public let expiresAt: String
}

public struct ParcelDelivery: Codable, Equatable, Sendable {
    public let parcelID: UUID
    public let status: ParcelDeliveryStatus
    public let paymentStatus: ParcelPaymentStatus
    public let refundStatus: ParcelRefundStatus
    public let deliveryMethod: DeliveryMethod
    public let pickup: AddressedGeoPoint
    public let dropoff: AddressedGeoPoint
    public let recipient: ParcelRecipient
    public let declaredContents: String
    public let declaredValue: Money
    public let deliveryFee: Money
    public let courierPayout: Money
    public let handoffCode: ParcelHandoffCode?

    private enum CodingKeys: String, CodingKey {
        case parcelID = "parcelId"
        case status
        case paymentStatus
        case refundStatus
        case deliveryMethod
        case pickup
        case dropoff
        case recipient
        case declaredContents
        case declaredValue
        case deliveryFee
        case courierPayout
        case handoffCode
    }
}

public struct CustomerParcelDelivery: Codable, Equatable, Sendable {
    public let parcel: ParcelDelivery
    public let audience: ParcelDeliveryAudience

    public init(parcel: ParcelDelivery, audience: ParcelDeliveryAudience) {
        self.parcel = parcel
        self.audience = audience
    }

    private enum CodingKeys: String, CodingKey {
        case audience
    }

    public init(from decoder: Decoder) throws {
        parcel = try ParcelDelivery(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audience = try container.decode(ParcelDeliveryAudience.self, forKey: .audience)
    }

    public func encode(to encoder: Encoder) throws {
        try parcel.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(audience, forKey: .audience)
    }
}

public struct ParcelAssignment: Codable, Equatable, Sendable {
    public let assignmentID: UUID
    public let assignmentStatus: ParcelAssignmentStatus
    public let offeredAt: String
    public let respondBy: String
    public let acknowledgedAt: String?
    public let distanceMeters: Double
    public let parcel: ParcelDelivery

    private enum CodingKeys: String, CodingKey {
        case assignmentID = "assignmentId"
        case assignmentStatus
        case offeredAt
        case respondBy
        case acknowledgedAt
        case distanceMeters
        case parcel
    }
}

public struct ParcelPartnerSnapshot: Codable, Equatable, Sendable {
    public let offer: ParcelAssignment?
    public let currentJob: ParcelAssignment?
}

public struct ParcelSafetyIncident: Codable, Equatable, Sendable {
    public let incidentID: UUID
    public let status: String
    public let emergencyNumber: String

    private enum CodingKeys: String, CodingKey {
        case incidentID = "incidentId"
        case status
        case emergencyNumber
    }
}

public protocol ParcelDeliveryClient: Sendable {
    func quote(
        deliveryMethod: DeliveryMethod,
        pickup: AddressedGeoPoint,
        dropoff: AddressedGeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelQuote

    func createParcel(
        quoteID: UUID,
        recipientName: String,
        recipientPhoneNumber: String,
        declaredContents: String,
        declaredValuePaise: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery

    func parcelSnapshot(
        parcelID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery

    func customerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> [CustomerParcelDelivery]

    func partnerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot

    func acknowledgeAssignment(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot

    func declineAssignment(
        assignmentID: UUID,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot

    func startToPickup(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot

    func confirmPickup(
        assignmentID: UUID,
        verificationCode: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot

    func startDelivery(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot

    func completeDelivery(
        assignmentID: UUID,
        verificationCode: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot

    func cancelParcel(
        parcelID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery

    func reportSafetyIncident(
        parcelID: UUID,
        incidentType: String,
        reportText: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelSafetyIncident
}

public struct SupabaseParcelDeliveryClient: ParcelDeliveryClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let deliveryMethod: DeliveryMethod?
        let pickup: AddressedGeoPoint?
        let dropoff: AddressedGeoPoint?
        let quoteId: UUID?
        let parcelId: UUID?
        let assignmentId: UUID?
        let recipientName: String?
        let recipientPhoneNumber: String?
        let declaredContents: String?
        let declaredValuePaise: Int?
        let reason: String?
        let verificationCode: String?
        let incidentType: String?
        let reportText: String?

        init(
            operation: String,
            deliveryMethod: DeliveryMethod? = nil,
            pickup: AddressedGeoPoint? = nil,
            dropoff: AddressedGeoPoint? = nil,
            quoteId: UUID? = nil,
            parcelId: UUID? = nil,
            assignmentId: UUID? = nil,
            recipientName: String? = nil,
            recipientPhoneNumber: String? = nil,
            declaredContents: String? = nil,
            declaredValuePaise: Int? = nil,
            reason: String? = nil,
            verificationCode: String? = nil,
            incidentType: String? = nil,
            reportText: String? = nil
        ) {
            self.operation = operation
            self.deliveryMethod = deliveryMethod
            self.pickup = pickup
            self.dropoff = dropoff
            self.quoteId = quoteId
            self.parcelId = parcelId
            self.assignmentId = assignmentId
            self.recipientName = recipientName
            self.recipientPhoneNumber = recipientPhoneNumber
            self.declaredContents = declaredContents
            self.declaredValuePaise = declaredValuePaise
            self.reason = reason
            self.verificationCode = verificationCode
            self.incidentType = incidentType
            self.reportText = reportText
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func quote(
        deliveryMethod: DeliveryMethod,
        pickup: AddressedGeoPoint,
        dropoff: AddressedGeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelQuote {
        try await invoke(
            Request(
                operation: "quote",
                deliveryMethod: deliveryMethod,
                pickup: pickup,
                dropoff: dropoff
            ),
            key: idempotencyKey
        )
    }

    public func createParcel(
        quoteID: UUID,
        recipientName: String,
        recipientPhoneNumber: String,
        declaredContents: String,
        declaredValuePaise: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery {
        try await invoke(
            Request(
                operation: "createParcel",
                quoteId: quoteID,
                recipientName: recipientName,
                recipientPhoneNumber: recipientPhoneNumber,
                declaredContents: declaredContents,
                declaredValuePaise: declaredValuePaise
            ),
            key: idempotencyKey
        )
    }

    public func parcelSnapshot(
        parcelID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery {
        try await invoke(
            Request(operation: "parcelSnapshot", parcelId: parcelID),
            key: idempotencyKey
        )
    }

    public func customerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> [CustomerParcelDelivery] {
        try await invoke(Request(operation: "customerSnapshot"), key: idempotencyKey)
    }

    public func partnerSnapshot(
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await invoke(Request(operation: "partnerSnapshot"), key: idempotencyKey)
    }

    public func acknowledgeAssignment(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await assignment(
            operation: "acknowledgeAssignment",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func declineAssignment(
        assignmentID: UUID,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await invoke(
            Request(
                operation: "declineAssignment",
                assignmentId: assignmentID,
                reason: reason
            ),
            key: idempotencyKey
        )
    }

    public func startToPickup(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await assignment(
            operation: "startToPickup",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func confirmPickup(
        assignmentID: UUID,
        verificationCode: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await assignment(
            operation: "confirmPickup",
            assignmentID: assignmentID,
            verificationCode: verificationCode,
            idempotencyKey: idempotencyKey
        )
    }

    public func startDelivery(
        assignmentID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await assignment(
            operation: "startDelivery",
            assignmentID: assignmentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func completeDelivery(
        assignmentID: UUID,
        verificationCode: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await assignment(
            operation: "completeDelivery",
            assignmentID: assignmentID,
            verificationCode: verificationCode,
            idempotencyKey: idempotencyKey
        )
    }

    public func cancelParcel(
        parcelID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelDelivery {
        try await invoke(
            Request(operation: "cancelParcel", parcelId: parcelID, reason: reason),
            key: idempotencyKey
        )
    }

    public func reportSafetyIncident(
        parcelID: UUID,
        incidentType: String,
        reportText: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelSafetyIncident {
        try await invoke(
            Request(
                operation: "reportSafetyIncident",
                parcelId: parcelID,
                incidentType: incidentType,
                reportText: reportText
            ),
            key: idempotencyKey
        )
    }

    private func assignment(
        operation: String,
        assignmentID: UUID,
        verificationCode: String? = nil,
        idempotencyKey: IdempotencyKey
    ) async throws -> ParcelPartnerSnapshot {
        try await invoke(
            Request(
                operation: operation,
                assignmentId: assignmentID,
                verificationCode: verificationCode
            ),
            key: idempotencyKey
        )
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke(
            "parcel-deliveries",
            request: request,
            idempotencyKey: key
        )
    }
}
