import Foundation
import MarketplaceFoundation

public enum DastakV1MissionStatus: String, Codable, Equatable, Sendable {
    case assigned = "ASSIGNED"
    case enRouteToPickups = "EN_ROUTE_TO_PICKUPS"
    case pickupInProgress = "PICKUP_IN_PROGRESS"
    case allPackagesPickedUp = "ALL_PACKAGES_PICKED_UP"
    case outForDelivery = "OUT_FOR_DELIVERY"
    case arrived = "ARRIVED"
    case deliveryRecovery = "DELIVERY_RECOVERY"
}

public enum DastakV1PickupStatus: String, Codable, Equatable, Sendable {
    case pending = "PENDING"
    case arrived = "ARRIVED"
    case completed = "COMPLETED"
}

public struct DastakV1RiderOffer: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let missionID: UUID
    public let displayOrderNumber: String
    public let transportType: String
    public let distanceMeters: Double
    public let respondBy: String
    public let secondsRemaining: Int
    public let pickupCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, displayOrderNumber, transportType, distanceMeters, respondBy
        case secondsRemaining, pickupCount
        case missionID = "missionId"
    }
}

public struct DastakV1MissionAddress: Codable, Equatable, Sendable {
    public let label: String?
    public let line1: String
    public let line2: String?
    public let landmark: String?
    public let city: String?
    public let state: String?
    public let postalCode: String?
    public let latitude: Double
    public let longitude: Double

    public var displayLine: String {
        [line2, line1, landmark, city, state, postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, item in
                if !result.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
                    result.append(item)
                }
            }
            .joined(separator: ", ")
    }
}

public struct DastakV1MissionRecipient: Codable, Equatable, Sendable {
    public let name: String
    public let phoneNumber: String
}

public struct DastakV1CustomerDestination: Codable, Equatable, Sendable {
    public let address: DastakV1MissionAddress
    public let recipient: DastakV1MissionRecipient?
}

public struct DastakV1MissionBranch: Codable, Equatable, Sendable {
    public let id: UUID?
    public let displayName: String
    public let address: DastakV1MissionAddress
}

public struct DastakV1MissionPickupStop: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sequence: Int
    public let status: DastakV1PickupStatus?
    public let ready: Bool
    public let runningLate: Bool
    public let packageCount: Int?
    public let waitingSeconds: Int
    public let branch: DastakV1MissionBranch
}

public enum DastakV1CollectionState: String, Codable, Equatable, Sendable {
    case notRequired = "NOT_REQUIRED"
    case paymentDueAtDelivery = "PAYMENT_DUE_AT_DELIVERY"
    case retryNeeded = "COLLECTION_RETRY_NEEDED"
    case collected = "PAYMENT_COLLECTED"
}

public enum DastakV1CollectionOutcome: String, Codable, Equatable, Sendable {
    case collected = "COLLECTED"
    case failed = "FAILED"
}

public enum DastakV1CollectionMethod: String, Codable, CaseIterable, Equatable, Sendable {
    case cash = "CASH"
    case upi = "UPI"
}

public struct DastakV1LaunchCollection: Codable, Equatable, Sendable {
    public let required: Bool
    public let state: DastakV1CollectionState
    public let amountPaise: Int?
    public let currencyCode: String?
    public let methods: [DastakV1CollectionMethod]
    public let canRecord: Bool
    public let lastOutcome: DastakV1CollectionOutcome?
    public let lastMethod: DastakV1CollectionMethod?
    public let failureReason: String?
    public let attemptedAt: String?
    public let collectedAt: String?

    public var amount: Money? { amountPaise.map { Money(paise: $0) } }
}

public struct DastakV1FinalVerification: Codable, Equatable, Sendable {
    public let status: String
    public let failedAttempts: Int
    public let evidencePresent: Bool
}

public struct DastakV1DeliveryMissionSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayOrderNumber: String
    public let status: DastakV1MissionStatus
    public let version: Int
    public let pickupCount: Int
    public let pickupStops: [DastakV1MissionPickupStop]
    public let customerDestination: DastakV1CustomerDestination?
    public let finalVerification: DastakV1FinalVerification?
    public let launchCollection: DastakV1LaunchCollection?
    public let canStartFinalDelivery: Bool
    public let canArriveCustomer: Bool
    public let canCaptureDeliveryEvidence: Bool
    public let canVerifyDelivery: Bool
    public let canCancelBeforePickup: Bool
    public let mustUseDeliveryRecovery: Bool
}

public struct DastakV1DeliveryDispatchSnapshot: Codable, Equatable, Sendable {
    public let offer: DastakV1RiderOffer?
    public let currentMission: DastakV1DeliveryMissionSnapshot?
}

public protocol DastakV1DeliveryClient: Sendable {
    func snapshot(idempotencyKey: IdempotencyKey) async throws -> DastakV1DeliveryDispatchSnapshot
    func accept(offerID: UUID, idempotencyKey: IdempotencyKey) async throws -> DastakV1DeliveryDispatchSnapshot
    func decline(offerID: UUID, reason: String?, idempotencyKey: IdempotencyKey) async throws -> DastakV1DeliveryDispatchSnapshot
    func advance(
        operation: String,
        missionID: UUID,
        stopID: UUID?,
        accountedPackageCount: Int?,
        verificationCode: String?,
        objectPath: String?,
        reason: String?,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1DeliveryDispatchSnapshot
    func recordCollection(
        missionID: UUID,
        outcome: DastakV1CollectionOutcome,
        method: DastakV1CollectionMethod,
        reference: String?,
        failureReason: String?,
        expectedMissionVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1DeliveryDispatchSnapshot
}

public struct SupabaseDastakV1DeliveryClient: DastakV1DeliveryClient {
    private struct Request: Encodable, Sendable {
        let operation: String
        let offerId: UUID?
        let missionId: UUID?
        let stopId: UUID?
        let accountedPackageCount: Int?
        let verificationCode: String?
        let objectPath: String?
        let reason: String?
        let outcome: DastakV1CollectionOutcome?
        let method: DastakV1CollectionMethod?
        let collectionReference: String?
        let failureReason: String?
        let expectedMissionVersion: Int?

        init(
            operation: String,
            offerId: UUID? = nil,
            missionId: UUID? = nil,
            stopId: UUID? = nil,
            accountedPackageCount: Int? = nil,
            verificationCode: String? = nil,
            objectPath: String? = nil,
            reason: String? = nil,
            outcome: DastakV1CollectionOutcome? = nil,
            method: DastakV1CollectionMethod? = nil,
            collectionReference: String? = nil,
            failureReason: String? = nil,
            expectedMissionVersion: Int? = nil
        ) {
            self.operation = operation
            self.offerId = offerId
            self.missionId = missionId
            self.stopId = stopId
            self.accountedPackageCount = accountedPackageCount
            self.verificationCode = verificationCode
            self.objectPath = objectPath
            self.reason = reason
            self.outcome = outcome
            self.method = method
            self.collectionReference = collectionReference
            self.failureReason = failureReason
            self.expectedMissionVersion = expectedMissionVersion
        }
    }

    private let functions: any FunctionClient

    public init(functions: any FunctionClient) {
        self.functions = functions
    }

    public func snapshot(idempotencyKey: IdempotencyKey) async throws -> DastakV1DeliveryDispatchSnapshot {
        try await invoke(Request(operation: "v1PartnerSnapshot"), key: idempotencyKey)
    }

    public func accept(offerID: UUID, idempotencyKey: IdempotencyKey) async throws -> DastakV1DeliveryDispatchSnapshot {
        try await invoke(Request(operation: "v1AcceptOffer", offerId: offerID), key: idempotencyKey)
    }

    public func decline(offerID: UUID, reason: String?, idempotencyKey: IdempotencyKey) async throws -> DastakV1DeliveryDispatchSnapshot {
        try await invoke(Request(operation: "v1DeclineOffer", offerId: offerID, reason: reason), key: idempotencyKey)
    }

    public func advance(
        operation: String,
        missionID: UUID,
        stopID: UUID? = nil,
        accountedPackageCount: Int? = nil,
        verificationCode: String? = nil,
        objectPath: String? = nil,
        reason: String? = nil,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1DeliveryDispatchSnapshot {
        try await invoke(Request(
            operation: operation,
            missionId: missionID,
            stopId: stopID,
            accountedPackageCount: accountedPackageCount,
            verificationCode: verificationCode,
            objectPath: objectPath,
            reason: reason
        ), key: idempotencyKey)
    }

    public func recordCollection(
        missionID: UUID,
        outcome: DastakV1CollectionOutcome,
        method: DastakV1CollectionMethod,
        reference: String?,
        failureReason: String?,
        expectedMissionVersion: Int,
        idempotencyKey: IdempotencyKey
    ) async throws -> DastakV1DeliveryDispatchSnapshot {
        try await invoke(Request(
            operation: "v1RecordLaunchCollection",
            missionId: missionID,
            outcome: outcome,
            method: method,
            collectionReference: reference,
            failureReason: failureReason,
            expectedMissionVersion: expectedMissionVersion
        ), key: idempotencyKey)
    }

    private func invoke<Response: Decodable & Sendable>(
        _ request: Request,
        key: IdempotencyKey
    ) async throws -> Response {
        try await functions.invoke("courier-dispatch", request: request, idempotencyKey: key)
    }
}
