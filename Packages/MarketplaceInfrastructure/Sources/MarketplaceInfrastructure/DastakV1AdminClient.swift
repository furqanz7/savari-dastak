import Foundation
import MarketplaceFoundation

public struct DastakV1AdminOrder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayOrderNumber: String
    public let orderType: String
    public let status: String
    public let version: Int
    public let paidAt: String?
    public let updatedAt: String
    public let deliveredAt: String?
}

public struct DastakV1AdminLaunchCommitment: Codable, Equatable, Sendable {
    public let id: UUID
    public let optionCode: String
    public let customerID: UUID
    public let amountPaise: Int
    public let currencyCode: String
    public let securedAt: String
    public let reservationExpiresAt: String
    public let committedAt: String
    public let version: Int

    private enum CodingKeys: String, CodingKey {
        case id, optionCode, amountPaise, currencyCode, securedAt
        case reservationExpiresAt, committedAt, version
        case customerID = "customerId"
    }
}

public struct DastakV1AdminCollectionAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let outcome: String
    public let method: String
    public let riderID: UUID
    public let missionID: UUID
    public let reference: String?
    public let reason: String?
    public let attemptedAt: String
    public let collectedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, outcome, method, reference, reason, attemptedAt, collectedAt
        case riderID = "riderId"
        case missionID = "missionId"
    }
}

public struct DastakV1AdminPlatformFee: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let amountPaise: Int
    public let currencyCode: String
    public let postedAt: String
    public let balanced: Bool

    private enum CodingKeys: String, CodingKey {
        case amountPaise, currencyCode, postedAt, balanced
        case transactionID = "transactionId"
    }
}

public struct DastakV1AdminLaunchPayment: Codable, Equatable, Sendable {
    public let commitment: DastakV1AdminLaunchCommitment?
    public let collectionStatus: String
    public let attempts: [DastakV1AdminCollectionAttempt]
    public let platformFee: DastakV1AdminPlatformFee?
}

public struct DastakV1AdminExecutionTrace: Codable, Equatable, Sendable {
    public let order: DastakV1AdminOrder
    public let launchPayment: DastakV1AdminLaunchPayment?
}

public enum DastakAdminRole: String, Codable, Equatable, Sendable {
    case superadmin = "SUPERADMIN"
    case executiveAdmin = "EXECUTIVE_ADMIN"

    public var displayName: String {
        switch self {
        case .superadmin: "Superadmin"
        case .executiveAdmin: "Executive Admin"
        }
    }
}

public struct DastakAdminSlot: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { slot }
    public let slot: Int
    public let role: DastakAdminRole
    public let email: String?
    public let linked: Bool
    public let version: Int
}

public struct DastakAdminAccessSnapshot: Codable, Equatable, Sendable {
    public let role: DastakAdminRole
    public let canManageAdmins: Bool
    public let slots: [DastakAdminSlot]
}

public struct DastakAdminCommandCenter: Codable, Equatable, Sendable {
    public struct ActionQueue: Codable, Equatable, Sendable {
        public let merchantApplications: Int
        public let deliveryApplications: Int
        public let openIncidents: Int
        public let riderEscalations: Int
        public let activePauses: Int
    }
    public struct Identities: Codable, Equatable, Sendable {
        public let activeAccounts: Int
        public let customers: Int
        public let merchants: Int
        public let deliveryPartners: Int
        public let deletedPersonas: Int
        public let recoveryEligiblePhones: Int
    }
    public struct Commerce: Codable, Equatable, Sendable {
        public let activeOrders: Int
        public let awaitingPayment: Int
        public let preparingFulfilments: Int
        public let readyFulfilments: Int
        public let activeMissions: Int
        public let deliveredToday: Int
    }
    public struct Network: Codable, Equatable, Sendable {
        public let activeOrganizations: Int
        public let activeBranches: Int
        public let onlineRiders: Int
        public let assignedRiders: Int
    }
    public struct Catalogue: Codable, Equatable, Sendable {
        public let total: Int
        public let active: Int
        public let draft: Int
        public let needsReview: Int
        public let missingPrimaryImage: Int
    }

    public let observedAt: String
    public let actionQueue: ActionQueue
    public let identities: Identities
    public let commerce: Commerce
    public let network: Network
    public let catalogue: Catalogue
}

public enum DastakAdminPersona: String, Codable, Equatable, Sendable {
    case customer = "CUSTOMER"
    case merchant = "MERCHANT"
    case delivery = "DELIVERY"
    case admin = "ADMIN"
}

public enum DastakAdminPersonaState: String, Codable, Equatable, Sendable {
    case active = "ACTIVE"
    case deleted = "DELETED"
}

public struct DastakAdminNetworkPerson: Codable, Equatable, Identifiable, Sendable {
    public struct Persona: Codable, Equatable, Sendable {
        public let persona: DastakAdminPersona
        public let state: DastakAdminPersonaState
        public let activatedAt: String
        public let deletedAt: String?
        public let version: Int
    }
    public struct Customer: Codable, Equatable, Sendable {
        public let orderCount: Int
        public let activeOrderCount: Int
    }
    public struct Merchant: Codable, Equatable, Sendable {
        public let applicationStatus: String
        public let businessName: String
        public let submittedAt: String
        public let reviewedAt: String?
        public let organizationName: String?
        public let organizationStatus: String?
        public let branchCount: Int
    }
    public struct Delivery: Codable, Equatable, Sendable {
        public let applicationStatus: String
        public let deliveryMethod: String
        public let submittedAt: String
        public let reviewedAt: String?
        public let availability: String?
        public let lastSeenAt: String?
        public let activeMissionCount: Int
    }

    public let id: UUID
    public let displayName: String
    public let email: String?
    public let phoneNumber: String
    public let phoneVerified: Bool
    public let accountState: String
    public let adminRole: DastakAdminRole?
    public let createdAt: String
    public let updatedAt: String
    public let lastSignInAt: String?
    public let personas: [Persona]
    public let customer: Customer
    public let merchant: Merchant?
    public let delivery: Delivery?
}

public struct DastakAdminNetworkCursor: Codable, Equatable, Sendable {
    public let updatedAt: String
    public let accountId: UUID
}

public struct DastakAdminNetworkPage: Codable, Equatable, Sendable {
    public let people: [DastakAdminNetworkPerson]
    public let hasMore: Bool
    public let nextCursor: DastakAdminNetworkCursor?
}

public struct DastakAdminCatalogueSKU: Codable, Equatable, Identifiable, Sendable {
    public struct PrimaryImage: Codable, Equatable, Sendable {
        public let id: UUID
        public let imageKey: String
        public let status: String
        public let rightsStatus: String
        public let sourceType: String
    }

    public let id: UUID
    public let name: String
    public let brandName: String?
    public let packSize: String
    public let listPricePaise: Int?
    public let sellingPricePaise: Int?
    public let currencyCode: String
    public let status: String
    public let qaStatus: String
    public let activationReady: Bool
    public let activationBlockers: [String]
    public let imageCount: Int
    public let aliasCount: Int
    public let identifierCount: Int
    public let primaryImage: PrimaryImage?
    public let version: Int
    public let updatedAt: String
}

public struct DastakAdminCatalogueCursor: Codable, Equatable, Sendable {
    public let name: String
    public let skuId: UUID
}

public struct DastakAdminCataloguePage: Codable, Equatable, Sendable {
    public let skus: [DastakAdminCatalogueSKU]
    public let hasMore: Bool
    public let nextCursor: DastakAdminCatalogueCursor?
}

public struct DastakAdminCatalogueMutation: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let listPricePaise: Int
    public let sellingPricePaise: Int
    public let currencyCode: String
    public let status: String
    public let version: Int
    public let updatedAt: String
}

public enum DastakAdminOperationalPauseScope: String, Codable, Equatable, CaseIterable, Sendable {
    case retailZone = "ZONE_RETAIL"
    case foodZone = "ZONE_FOOD"
    case mixedZone = "ZONE_MIXED"
    case merchantBranch = "MERCHANT_BRANCH"
    case riderAssignments = "RIDER_ASSIGNMENTS"

    public var displayName: String {
        switch self {
        case .retailZone: "Retail zone"
        case .foodZone: "Food zone"
        case .mixedZone: "Mixed zone"
        case .merchantBranch: "Merchant branch"
        case .riderAssignments: "Rider assignments"
        }
    }
}

public struct DastakAdminOperationalSafety: Codable, Equatable, Sendable {
    public struct Permissions: Codable, Equatable, Sendable {
        public let canManageRiderEscalations: Bool
        public let canManageOperationalPauses: Bool
    }

    public struct Pause: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let scope: DastakAdminOperationalPauseScope
        public let targetID: UUID
        public let active: Bool
        public let reason: String
        public let activatedAt: String?
        public let clearedAt: String?
        public let version: Int

        private enum CodingKeys: String, CodingKey {
            case id, scope, active, reason, activatedAt, clearedAt, version
            case targetID = "targetId"
        }
    }

    public struct RiderEscalation: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID { missionID }
        public let missionID: UUID
        public let orderID: UUID
        public let displayOrderNumber: String
        public let status: String
        public let riderID: UUID?
        public let transportType: String?
        public let lastContactAt: String?
        public let lastProgressAt: String?
        public let stallDetectedAt: String?
        public let unresponsiveDetectedAt: String?
        public let escalationState: String
        public let escalatedAt: String?
        public let escalationReason: String?
        public let custodyStarted: Bool
        public let version: Int

        private enum CodingKeys: String, CodingKey {
            case displayOrderNumber, status, transportType, lastContactAt, lastProgressAt
            case stallDetectedAt, unresponsiveDetectedAt, escalationState, escalatedAt
            case escalationReason, custodyStarted, version
            case missionID = "missionId"
            case orderID = "orderId"
            case riderID = "riderId"
        }
    }

    public let permissions: Permissions
    public let pauses: [Pause]
    public let riderEscalations: [RiderEscalation]
}

public struct DastakAdminOperationalAlertValues: Codable, Equatable, Sendable {
    public let outboxPendingCount: Int
    public let notificationPendingCount: Int
    public let paymentReconciliationOpenCount: Int
    public let riderEscalationOpenCount: Int
    public let merchantUnreachableBranchCount: Int
    public let customerUnreachableDueCount: Int
}

public struct DastakAdminSystemHealth: Codable, Equatable, Sendable {
    public struct Incident: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let invariantKey: String
        public let entityType: String
        public let entityID: UUID
        public let firstDetectedAt: String
        public let lastDetectedAt: String
        public let occurrenceCount: Int

        private enum CodingKeys: String, CodingKey {
            case id, invariantKey, entityType, firstDetectedAt, lastDetectedAt, occurrenceCount
            case entityID = "entityId"
        }
    }

    public struct MonitorRun: Codable, Equatable, Sendable {
        public let id: UUID
        public let findingCount: Int
        public let startedAt: String
        public let completedAt: String
    }

    public struct Outbox: Codable, Equatable, Sendable {
        public let pending: Int
        public let deadLetter: Int
        public let oldestPendingSeconds: Int
        public let staleThresholdSeconds: Int
    }

    public struct Notifications: Codable, Equatable, Sendable {
        public let pending: Int
        public let inFlight: Int
        public let deadLetter: Int
    }

    public struct OperationalAlerts: Codable, Equatable, Sendable {
        public let breached: Bool
        public let counts: DastakAdminOperationalAlertValues
        public let thresholds: DastakAdminOperationalAlertValues
    }

    public let healthy: Bool
    public let workerConfigured: Bool
    public let openCriticalIncidentCount: Int
    public let incidents: [Incident]
    public let lastMonitorRun: MonitorRun?
    public let outbox: Outbox
    public let notifications: Notifications
    public let paymentReconciliationOpen: Int
    public let operationalAlerts: OperationalAlerts
    public let observedAt: String
}

public struct DastakAdminRiderEscalationMutation: Codable, Equatable, Sendable {
    public let missionID: UUID
    public let status: String
    public let escalationState: String
    public let version: Int

    private enum CodingKeys: String, CodingKey {
        case status, escalationState, version
        case missionID = "missionId"
    }
}

public struct DastakAdminOperationalPauseMutation: Codable, Equatable, Sendable {
    public let id: UUID
    public let scope: DastakAdminOperationalPauseScope
    public let targetID: UUID
    public let active: Bool
    public let reason: String
    public let version: Int
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, scope, active, reason, version, updatedAt
        case targetID = "targetId"
    }
}

public struct DastakAdminRoyaltyPayout: Codable, Equatable, Identifiable, Sendable {
    public struct Destination: Codable, Equatable, Sendable {
        public let type: String
        public let displayLabel: String
    }

    public let id: UUID
    public let subjectType: String
    public let subjectID: UUID
    public let amountPaise: Int
    public let effectiveStatus: String
    public let destinationSnapshot: Destination
    public let provider: String?
    public let providerPayoutReference: String?
    public let providerStatus: String?
    public let reconciliationState: String?
    public let utr: String?
    public let requestedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, subjectType, amountPaise, effectiveStatus, destinationSnapshot
        case provider, providerPayoutReference, providerStatus, reconciliationState, utr, requestedAt
        case subjectID = "subjectId"
    }
}

public protocol DastakV1AdminClient: Sendable {
    func orders(limit: Int, idempotencyKey: IdempotencyKey) async throws -> [DastakV1AdminOrder]
    func trace(orderID: UUID, idempotencyKey: IdempotencyKey) async throws -> DastakV1AdminExecutionTrace
    func access(idempotencyKey: IdempotencyKey) async throws -> DastakAdminAccessSnapshot
    func commandCenter(idempotencyKey: IdempotencyKey) async throws -> DastakAdminCommandCenter
    func systemHealth(idempotencyKey: IdempotencyKey) async throws -> DastakAdminSystemHealth
    func operationalSafety(idempotencyKey: IdempotencyKey) async throws -> DastakAdminOperationalSafety
    func manageRiderEscalation(
        missionID: UUID,
        action: String,
        reason: String,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminRiderEscalationMutation
    func setOperationalPause(
        scope: DastakAdminOperationalPauseScope,
        targetID: UUID,
        active: Bool,
        reason: String,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminOperationalPauseMutation
    func royaltyPayouts(limit: Int, idempotencyKey: IdempotencyKey) async throws -> [DastakAdminRoyaltyPayout]
    func evidenceDownloadURL(objectPath: String, idempotencyKey: IdempotencyKey) async throws -> EvidenceDownload
    func networkPage(
        query: String?,
        persona: DastakAdminPersona?,
        state: DastakAdminPersonaState?,
        limit: Int,
        cursor: DastakAdminNetworkCursor?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminNetworkPage
    func cataloguePage(
        query: String?,
        status: String?,
        qaStatus: String?,
        limit: Int,
        cursor: DastakAdminCatalogueCursor?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminCataloguePage
    func updateCatalogueSKU(
        id: UUID,
        expectedVersion: Int,
        listPricePaise: Int,
        sellingPricePaise: Int,
        status: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminCatalogueMutation
    func setExecutiveAdmin(
        slot: Int,
        email: String?,
        expectedVersion: Int,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminSlot
}

public struct SupabaseDastakV1AdminClient: DastakV1AdminClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let limit: Int?
        let orderId: UUID?
        let slot: Int?
        let email: String?
        let expectedVersion: Int?
        let reason: String?
        let query: String?
        let persona: DastakAdminPersona?
        let state: DastakAdminPersonaState?
        let cursor: DastakAdminNetworkCursor?
        let missionId: UUID?
        let action: String?
        let scope: DastakAdminOperationalPauseScope?
        let targetId: UUID?
        let active: Bool?

        init(
            operation: String,
            limit: Int? = nil,
            orderId: UUID? = nil,
            slot: Int? = nil,
            email: String? = nil,
            expectedVersion: Int? = nil,
            reason: String? = nil,
            query: String? = nil,
            persona: DastakAdminPersona? = nil,
            state: DastakAdminPersonaState? = nil,
            cursor: DastakAdminNetworkCursor? = nil,
            missionId: UUID? = nil,
            action: String? = nil,
            scope: DastakAdminOperationalPauseScope? = nil,
            targetId: UUID? = nil,
            active: Bool? = nil
        ) {
            self.operation = operation
            self.limit = limit
            self.orderId = orderId
            self.slot = slot
            self.email = email
            self.expectedVersion = expectedVersion
            self.reason = reason
            self.query = query
            self.persona = persona
            self.state = state
            self.cursor = cursor
            self.missionId = missionId
            self.action = action
            self.scope = scope
            self.targetId = targetId
            self.active = active
        }
    }

    private struct EvidenceRequest: Encodable, Sendable {
        let bucket = "dastak-evidence"
        let objectPath: String
        let operation = "download"
    }

    private struct PayoutCollection: Decodable, Sendable {
        let withdrawals: [DastakAdminRoyaltyPayout]
    }

    private struct CatalogueRequest: Encodable, Sendable {
        struct Patch: Encodable, Sendable {
            let listPricePaise: Int
            let sellingPricePaise: Int
            let status: String
        }
        let operation: String
        let query: String?
        let status: String?
        let qaStatus: String?
        let limit: Int?
        let cursor: DastakAdminCatalogueCursor?
        let skuId: UUID?
        let expectedVersion: Int?
        let patch: Patch?
    }

    private struct OrderCollection: Decodable, Sendable {
        let orders: [DastakV1AdminOrder]
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func orders(
        limit: Int = 50,
        idempotencyKey: IdempotencyKey
    ) async throws -> [DastakV1AdminOrder] {
        precondition((1...100).contains(limit))
        let collection: OrderCollection = try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "adminExecutionOrders",
                limit: limit
            ),
            idempotencyKey: idempotencyKey
        )
        return collection.orders
    }

    public func trace(
        orderID: UUID,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1AdminExecutionTrace {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "adminExecutionTrace",
                orderId: orderID
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func access(
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminAccessSnapshot {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "adminAccess"
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func commandCenter(
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminCommandCenter {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(operation: "adminCommandCenter"),
            idempotencyKey: idempotencyKey
        )
    }

    public func systemHealth(
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminSystemHealth {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(operation: "adminSystemHealth"),
            idempotencyKey: idempotencyKey
        )
    }

    public func operationalSafety(
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminOperationalSafety {
        try await functions.invoke(
            "dastak-v1-orders",
            request: Request(operation: "adminOperationalSafety"),
            idempotencyKey: idempotencyKey
        )
    }

    public func manageRiderEscalation(
        missionID: UUID,
        action: String,
        reason: String,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminRiderEscalationMutation {
        precondition(["RELEASE_REMATCH", "ENTER_DELIVERY_RECOVERY"].contains(action))
        precondition(expectedVersion > 0)
        return try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "manageRiderEscalation",
                expectedVersion: expectedVersion,
                reason: reason,
                missionId: missionID,
                action: action
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func setOperationalPause(
        scope: DastakAdminOperationalPauseScope,
        targetID: UUID,
        active: Bool,
        reason: String,
        expectedVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminOperationalPauseMutation {
        precondition(expectedVersion >= 0)
        return try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "setOperationalPause",
                expectedVersion: expectedVersion,
                reason: reason,
                scope: scope,
                targetId: targetID,
                active: active
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func royaltyPayouts(
        limit: Int = 100,
        idempotencyKey: IdempotencyKey
    ) async throws -> [DastakAdminRoyaltyPayout] {
        precondition((1...100).contains(limit))
        let collection: PayoutCollection = try await functions.invoke(
            "earnings",
            request: Request(operation: "adminRoyaltyPayouts", limit: limit),
            idempotencyKey: idempotencyKey
        )
        return collection.withdrawals
    }

    public func evidenceDownloadURL(
        objectPath: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> EvidenceDownload {
        precondition(!objectPath.isEmpty)
        return try await functions.invoke(
            "issue-evidence-url",
            request: EvidenceRequest(objectPath: objectPath),
            idempotencyKey: idempotencyKey
        )
    }

    public func networkPage(
        query: String?,
        persona: DastakAdminPersona?,
        state: DastakAdminPersonaState?,
        limit: Int = 50,
        cursor: DastakAdminNetworkCursor?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminNetworkPage {
        precondition((1...100).contains(limit))
        return try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "adminNetworkPage",
                limit: limit,
                query: query,
                persona: persona,
                state: state,
                cursor: cursor
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func cataloguePage(
        query: String?,
        status: String?,
        qaStatus: String?,
        limit: Int = 50,
        cursor: DastakAdminCatalogueCursor?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminCataloguePage {
        precondition((1...100).contains(limit))
        return try await functions.invoke(
            "dastak-v1-catalogue",
            request: CatalogueRequest(
                operation: "adminCataloguePage",
                query: query,
                status: status,
                qaStatus: qaStatus,
                limit: limit,
                cursor: cursor,
                skuId: nil,
                expectedVersion: nil,
                patch: nil
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func updateCatalogueSKU(
        id: UUID,
        expectedVersion: Int,
        listPricePaise: Int,
        sellingPricePaise: Int,
        status: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminCatalogueMutation {
        precondition(expectedVersion > 0)
        return try await functions.invoke(
            "dastak-v1-catalogue",
            request: CatalogueRequest(
                operation: "updateSku",
                query: nil,
                status: nil,
                qaStatus: nil,
                limit: nil,
                cursor: nil,
                skuId: id,
                expectedVersion: expectedVersion,
                patch: .init(
                    listPricePaise: listPricePaise,
                    sellingPricePaise: sellingPricePaise,
                    status: status
                )
            ),
            idempotencyKey: idempotencyKey
        )
    }

    public func setExecutiveAdmin(
        slot: Int,
        email: String?,
        expectedVersion: Int,
        reason: String,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakAdminSlot {
        precondition((1...2).contains(slot))
        precondition(expectedVersion > 0)
        return try await functions.invoke(
            "dastak-v1-orders",
            request: Request(
                operation: "setExecutiveAdmin",
                slot: slot,
                email: email,
                expectedVersion: expectedVersion,
                reason: reason
            ),
            idempotencyKey: idempotencyKey
        )
    }
}
