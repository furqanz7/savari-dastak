import Foundation
import MarketplaceFoundation

public enum ControlledCategoryScope: String, Codable, Equatable, Sendable {
    case medicine
    case tobacco
}

public enum ControlledTobaccoKind: String, Codable, Equatable, Sendable {
    case cigarette
    case cigar
    case rollingTobacco = "rolling_tobacco"
}

public enum ControlledReviewDecision: String, Codable, Equatable, Sendable {
    case approve
    case reject
    case suspend
}

public enum VisualAgeCheckResult: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case uncertain
}

public enum RestrictedHandoffState: String, Codable, Equatable, Sendable {
    case passed
    case returnRequired = "return_required"
}

public struct ControlledOrderMetadata: Codable, Equatable, Sendable {
    public let scope: ControlledCategoryScope
    public let policyVersion: String?
    public let requiresPrescription: Bool
    public let restrictedHandoffState: RestrictedHandoffState?
}

public struct AdultAttestation: Codable, Equatable, Sendable {
    public let attestationID: UUID
    public let policyVersion: String
    public let attestedAt: String

    private enum CodingKeys: String, CodingKey {
        case attestationID = "attestationId"
        case policyVersion
        case attestedAt
    }
}

public struct ControlledCategoryPolicy: Codable, Equatable, Sendable {
    public let policyID: UUID
    public let version: String
    public let minimumAge: Int
    public let allowedTobaccoKinds: [ControlledTobaccoKind]
    public let active: Bool
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case policyID = "policyId"
        case version
        case minimumAge
        case allowedTobaccoKinds
        case active
        case createdAt
    }
}

public enum ControlledComplianceState: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case rejected
    case suspended
}

public struct ControlledStoreCompliance: Codable, Equatable, Sendable {
    public let complianceID: UUID
    public let storeID: UUID
    public let scope: ControlledCategoryScope
    public let status: ControlledComplianceState
    public let evidenceObjectPath: String?
    public let validUntil: String?
    public let submittedAt: String
    public let reviewedAt: String?
    public let reviewReason: String?

    private enum CodingKeys: String, CodingKey {
        case complianceID = "complianceId"
        case storeID = "storeId"
        case scope
        case status
        case evidenceObjectPath
        case validUntil
        case submittedAt
        case reviewedAt
        case reviewReason
    }
}

public enum RestrictedExclusionKind: String, Codable, Equatable, Sendable {
    case school
    case college
}

public struct RestrictedExclusionZone: Codable, Equatable, Sendable {
    public let zoneID: UUID
    public let name: String
    public let kind: RestrictedExclusionKind
    public let center: GeoPoint
    public let radiusMeters: Int
    public let active: Bool

    private enum CodingKeys: String, CodingKey {
        case zoneID = "zoneId"
        case name
        case kind
        case center
        case radiusMeters
        case active
    }
}

public struct ControlledCatalogueSnapshot: Codable, Equatable, Sendable {
    public let serviceZoneID: UUID
    public let scope: ControlledCategoryScope
    public let policyVersion: String?
    public let stores: [CatalogueStore]
    public let categories: [CatalogueCategory]
    public let products: [CatalogueProduct]

    private enum CodingKeys: String, CodingKey {
        case serviceZoneID = "serviceZoneId"
        case scope
        case policyVersion
        case stores
        case categories
        case products
    }
}

public struct EvidenceDownload: Codable, Equatable, Sendable {
    public let signedURL: String
    public let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case signedURL = "signedUrl"
        case expiresIn
    }
}

public protocol ControlledCategoryClient: Sendable {
    func attestAdult(
        policyVersion: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> AdultAttestation
    func browse(
        scope: ControlledCategoryScope,
        at location: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledCatalogueSnapshot
    func quote(
        scope: ControlledCategoryScope,
        storeID: UUID,
        lines: [MerchantOrderLineInput],
        dropoff: GeoPoint,
        prescriptionEvidencePath: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderQuote
    func createOrder(
        quoteID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot
    func orderSnapshot(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot
    func submitStoreCompliance(
        scope: ControlledCategoryScope,
        evidenceObjectPath: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledStoreCompliance
    func reviewStoreCompliance(
        complianceID: UUID,
        decision: ControlledReviewDecision,
        validUntil: String?,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledStoreCompliance
    func submitProduct(
        productID: UUID,
        tobaccoKind: ControlledTobaccoKind?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueProduct
    func reviewProduct(
        productID: UUID,
        decision: ControlledReviewDecision,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueProduct
    func upsertPolicy(
        version: String,
        allowedTobaccoKinds: [ControlledTobaccoKind],
        active: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledCategoryPolicy
    func upsertExclusionZone(
        zoneID: UUID?,
        name: String,
        kind: RestrictedExclusionKind,
        center: GeoPoint,
        radiusMeters: Int,
        active: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> RestrictedExclusionZone
    func verifyRestrictedHandoff(
        assignmentID: UUID,
        verificationCode: String,
        visualAgeCheck: VisualAgeCheckResult,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot
    func confirmRestrictedReturn(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot
    func prescriptionDownloadURL(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> EvidenceDownload
}

public struct SupabaseControlledCategoryClient: ControlledCategoryClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let scope: ControlledCategoryScope?
        let location: GeoPoint?
        let storeId: UUID?
        let lines: [MerchantOrderLineInput]?
        let dropoff: GeoPoint?
        let prescriptionEvidencePath: String?
        let quoteId: UUID?
        let orderId: UUID?
        let policyVersion: String?
        let affirmedAdult: Bool?
        let affirmedNotForMinor: Bool?
        let evidenceObjectPath: String?
        let complianceId: UUID?
        let decision: ControlledReviewDecision?
        let validUntil: String?
        let reason: String?
        let productId: UUID?
        let tobaccoKind: ControlledTobaccoKind?
        let version: String?
        let allowedTobaccoKinds: [ControlledTobaccoKind]?
        let active: Bool?
        let zoneId: UUID?
        let name: String?
        let kind: RestrictedExclusionKind?
        let center: GeoPoint?
        let radiusMeters: Int?
        let assignmentId: UUID?
        let verificationCode: String?
        let visualAgeCheck: VisualAgeCheckResult?

        init(
            operation: String,
            scope: ControlledCategoryScope? = nil,
            location: GeoPoint? = nil,
            storeId: UUID? = nil,
            lines: [MerchantOrderLineInput]? = nil,
            dropoff: GeoPoint? = nil,
            prescriptionEvidencePath: String? = nil,
            quoteId: UUID? = nil,
            orderId: UUID? = nil,
            policyVersion: String? = nil,
            affirmedAdult: Bool? = nil,
            affirmedNotForMinor: Bool? = nil,
            evidenceObjectPath: String? = nil,
            complianceId: UUID? = nil,
            decision: ControlledReviewDecision? = nil,
            validUntil: String? = nil,
            reason: String? = nil,
            productId: UUID? = nil,
            tobaccoKind: ControlledTobaccoKind? = nil,
            version: String? = nil,
            allowedTobaccoKinds: [ControlledTobaccoKind]? = nil,
            active: Bool? = nil,
            zoneId: UUID? = nil,
            name: String? = nil,
            kind: RestrictedExclusionKind? = nil,
            center: GeoPoint? = nil,
            radiusMeters: Int? = nil,
            assignmentId: UUID? = nil,
            verificationCode: String? = nil,
            visualAgeCheck: VisualAgeCheckResult? = nil
        ) {
            self.operation = operation
            self.scope = scope
            self.location = location
            self.storeId = storeId
            self.lines = lines
            self.dropoff = dropoff
            self.prescriptionEvidencePath = prescriptionEvidencePath
            self.quoteId = quoteId
            self.orderId = orderId
            self.policyVersion = policyVersion
            self.affirmedAdult = affirmedAdult
            self.affirmedNotForMinor = affirmedNotForMinor
            self.evidenceObjectPath = evidenceObjectPath
            self.complianceId = complianceId
            self.decision = decision
            self.validUntil = validUntil
            self.reason = reason
            self.productId = productId
            self.tobaccoKind = tobaccoKind
            self.version = version
            self.allowedTobaccoKinds = allowedTobaccoKinds
            self.active = active
            self.zoneId = zoneId
            self.name = name
            self.kind = kind
            self.center = center
            self.radiusMeters = radiusMeters
            self.assignmentId = assignmentId
            self.verificationCode = verificationCode
            self.visualAgeCheck = visualAgeCheck
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func attestAdult(
        policyVersion: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> AdultAttestation {
        try await invoke(Request(
            operation: "attestAdult",
            policyVersion: policyVersion,
            affirmedAdult: true,
            affirmedNotForMinor: true
        ), key: idempotencyKey)
    }

    public func browse(
        scope: ControlledCategoryScope,
        at location: GeoPoint,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledCatalogueSnapshot {
        try await invoke(Request(operation: "browse", scope: scope, location: location), key: idempotencyKey)
    }

    public func quote(
        scope: ControlledCategoryScope,
        storeID: UUID,
        lines: [MerchantOrderLineInput],
        dropoff: GeoPoint,
        prescriptionEvidencePath: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderQuote {
        try await invoke(Request(
            operation: "quote",
            scope: scope,
            storeId: storeID,
            lines: lines,
            dropoff: dropoff,
            prescriptionEvidencePath: prescriptionEvidencePath
        ), key: idempotencyKey)
    }

    public func createOrder(quoteID: UUID, idempotencyKey: IdempotencyKey) async throws -> MerchantOrderSnapshot {
        try await invoke(Request(operation: "createOrder", quoteId: quoteID), key: idempotencyKey)
    }

    public func orderSnapshot(orderID: UUID, idempotencyKey: IdempotencyKey) async throws -> MerchantOrderSnapshot {
        try await invoke(Request(operation: "orderSnapshot", orderId: orderID), key: idempotencyKey)
    }

    public func submitStoreCompliance(
        scope: ControlledCategoryScope,
        evidenceObjectPath: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledStoreCompliance {
        try await invoke(Request(
            operation: "submitStoreCompliance",
            scope: scope,
            evidenceObjectPath: evidenceObjectPath
        ), key: idempotencyKey)
    }

    public func reviewStoreCompliance(
        complianceID: UUID,
        decision: ControlledReviewDecision,
        validUntil: String?,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledStoreCompliance {
        try await invoke(Request(
            operation: "reviewStoreCompliance",
            complianceId: complianceID,
            decision: decision,
            validUntil: validUntil,
            reason: reason
        ), key: idempotencyKey)
    }

    public func submitProduct(
        productID: UUID,
        tobaccoKind: ControlledTobaccoKind?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueProduct {
        try await invoke(Request(
            operation: "submitProduct",
            productId: productID,
            tobaccoKind: tobaccoKind
        ), key: idempotencyKey)
    }

    public func reviewProduct(
        productID: UUID,
        decision: ControlledReviewDecision,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CatalogueProduct {
        try await invoke(Request(
            operation: "reviewProduct",
            decision: decision,
            reason: reason,
            productId: productID
        ), key: idempotencyKey)
    }

    public func upsertPolicy(
        version: String,
        allowedTobaccoKinds: [ControlledTobaccoKind],
        active: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> ControlledCategoryPolicy {
        try await invoke(Request(
            operation: "upsertPolicy",
            version: version,
            allowedTobaccoKinds: allowedTobaccoKinds,
            active: active
        ), key: idempotencyKey)
    }

    public func upsertExclusionZone(
        zoneID: UUID?,
        name: String,
        kind: RestrictedExclusionKind,
        center: GeoPoint,
        radiusMeters: Int,
        active: Bool,
        idempotencyKey: IdempotencyKey
    ) async throws -> RestrictedExclusionZone {
        try await invoke(Request(
            operation: "upsertExclusionZone",
            active: active,
            zoneId: zoneID,
            name: name,
            kind: kind,
            center: center,
            radiusMeters: radiusMeters
        ), key: idempotencyKey)
    }

    public func verifyRestrictedHandoff(
        assignmentID: UUID,
        verificationCode: String,
        visualAgeCheck: VisualAgeCheckResult,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> CourierDispatchSnapshot {
        try await invoke(Request(
            operation: "verifyRestrictedHandoff",
            reason: reason,
            assignmentId: assignmentID,
            verificationCode: verificationCode,
            visualAgeCheck: visualAgeCheck
        ), key: idempotencyKey)
    }

    public func confirmRestrictedReturn(
        orderID: UUID,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> MerchantOrderSnapshot {
        try await invoke(Request(
            operation: "confirmRestrictedReturn",
            orderId: orderID,
            reason: reason
        ), key: idempotencyKey)
    }

    public func prescriptionDownloadURL(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> EvidenceDownload {
        try await invoke(Request(operation: "prescriptionDownloadURL", orderId: orderID), key: idempotencyKey)
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke("controlled-categories", request: request, idempotencyKey: key)
    }
}
