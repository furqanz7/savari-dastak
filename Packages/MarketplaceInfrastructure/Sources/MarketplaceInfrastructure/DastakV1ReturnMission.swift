import Foundation

public struct DastakV1ReturnMission: Codable, Equatable, Identifiable, Sendable {
    public struct Verification: Codable, Equatable, Sendable {
        public let status: String
        public let failedAttempts: Int
    }
    public struct Evidence: Codable, Equatable, Identifiable, Sendable {
        public let id: UUID
        public let objectPath: String
        public let contentType: String
        public let capturedAt: String
    }
    public struct Address: Codable, Equatable, Sendable {
        public let line1: String
        public let line2: String?
        public let city: String?
        public let state: String?
        public let postalCode: String?
        public let latitude: Double?
        public let longitude: Double?
        public var display: String { [line2, line1, city, state, postalCode].compactMap { $0 }.joined(separator: ", ") }
    }
    public struct Destination: Codable, Equatable, Sendable {
        public let address: Address
        public let recipient: DastakV1MissionRecipient?
    }
    public struct Stop: Codable, Equatable, Identifiable, Sendable {
        public struct Branch: Codable, Equatable, Sendable {
            public struct Location: Codable, Equatable, Sendable {
                public let latitude: Double
                public let longitude: Double
            }
            public let id: UUID
            public let displayName: String
            public let address: Address
            public let location: Location?
        }
        public let id: UUID
        public let sequence: Int
        public let status: String
        public let packageCount: Int
        public let arrivedAt: String?
        public let completedAt: String?
        public let verificationStatus: String
        public let failedAttempts: Int
        public let arrival: DastakArrivalEligibility?
        public let canArrive: Bool?
        public let branch: Branch
    }
    public let id: UUID
    public let returnId: UUID
    public let orderId: UUID
    public let status: String
    public let version: Int
    public let transportType: String
    public let assignedAt: String
    public let arrivedCustomerAt: String?
    public let pickupCompletedAt: String?
    public let completedAt: String?
    public let customerDestination: Destination
    public let packageCount: Int
    public let pickupVerification: Verification
    public let evidence: [Evidence]
    public let stops: [Stop]
    public let customerArrival: DastakArrivalEligibility?
    public let canArriveCustomer: Bool
    public let canCaptureEvidence: Bool
    public let canVerifyPickup: Bool
    public let canCompleteReturnStops: Bool

    public var isValid: Bool {
        guard version > 0 && packageCount > 0 && !stops.isEmpty
            && ["ASSIGNED", "AT_CUSTOMER", "RETURNING_TO_MERCHANTS", "COMPLETED"].contains(status)
            && ["INACTIVE", "ACTIVE", "CONSUMED", "BLOCKED"].contains(pickupVerification.status)
            && pickupVerification.failedAttempts >= 0
            && Set(stops.map(\.id)).count == stops.count
            && Set(stops.map(\.sequence)).count == stops.count
            && stops.allSatisfy({ $0.sequence > 0 && $0.packageCount > 0 && $0.failedAttempts >= 0
                && ["PENDING", "ARRIVED", "COMPLETED"].contains($0.status)
                && ["INACTIVE", "ACTIVE", "CONSUMED", "BLOCKED"].contains($0.verificationStatus) }) else { return false }
        var total = 0
        for stop in stops {
            let addition = total.addingReportingOverflow(stop.packageCount)
            guard !addition.overflow else { return false }
            total = addition.partialValue
        }
        return total == packageCount
    }
}

public struct DastakV1CompletedMission: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let orderId: UUID
    public let status: String
    public let verificationStatus: String
    public let packageCount: Int
    public let deliveredAt: String
}

public struct DastakDeliveryWorkHistory: Decodable, Sendable {
    public struct Item: Decodable, Equatable, Identifiable, Sendable {
        public var id: String { kind + ":" + workId.uuidString }
        public let kind: String
        public let workId: UUID
        public let reference: String
        public let status: String
        public let startedAt: String
        public let endedAt: String
        public let packageCount: Int?
        public let payoutPaise: Int?
        public let outcome: String
    }
    public let items: [Item]
}
