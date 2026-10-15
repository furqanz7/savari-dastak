import Foundation

/// Branch-authorized return stops. One return can visit more than one branch.
public struct DastakV1MerchantReturnReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { returnStopId }
    public let returnId: UUID
    public let returnMissionId: UUID
    public let returnStopId: UUID
    public let orderId: UUID
    public let status: String
    public let packageCount: Int
    public let verificationStatus: String?
    public let receiptCode: String?
    public let arrivedAt: String?
    public let completedAt: String?
    public let branch: DastakV1MerchantBranch
}

/// Organization-wide ledger entries, not branch earnings or a payout command.
public struct DastakV1MerchantSettlement: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let orderId: UUID
    public let fulfilmentId: UUID?
    public let entryType: String
    public let status: String
    public let calculationStatus: String
    public let amountPaise: Int?
    public let currency: String
    public let eligibleAt: String?
    public let settledAt: String?
}
