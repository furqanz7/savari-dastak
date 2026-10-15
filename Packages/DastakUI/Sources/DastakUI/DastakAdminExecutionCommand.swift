import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

enum DastakAdminExecutionAction: String, Codable, CaseIterable, Sendable {
    case offer = "createExactSkuRecoveryOffer", fail = "failExactSkuRecovery"
    case delivery = "manageDeliveryRecovery", issue = "decideCustomerIssue"
    case rider = "assignReturnRider", refund = "processRefund"
    case settlement = "finalizeSettlementCalculation"
    case handoff = "authorizeExceptionalDeliveryHandoff", cancel = "adminCancelOrder"
    var title: String {
        switch self {
        case .offer: "Offer exact-SKU recovery"
        case .fail: "End exact-SKU recovery"
        case .delivery: "Resolve delivery recovery"
        case .issue: "Review customer issue"
        case .rider: "Assign return rider"
        case .refund: "Submit approved refund"
        case .settlement: "Calculate settlement"
        case .handoff: "Authorize exceptional handoff"
        case .cancel: "Cancel unpaid order"
        }
    }
}

/// Only these fields can leave the device. Server trace records are never used as write bodies.
struct DastakAdminExecutionRequest: Codable, Equatable, Sendable {
    struct Address: Codable, Equatable, Sendable {
        let line1: String
        let latitude: Double
        let longitude: Double
        var valid: Bool { !line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && line1.count <= 500 && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    }
    let operation: DastakAdminExecutionAction
    var orderId: UUID?
    var recoveryCaseId: UUID?
    var branchId: UUID?
    var issueId: UUID?
    var returnMissionId: UUID?
    var riderId: UUID?
    var refundId: UUID?
    var settlementEntryId: UUID?
    var missionId: UUID?
    var deliveryEvidenceId: UUID?
    var expectedVersion: Int?
    var expectedMissionVersion: Int?
    var entityType: String?
    var reason: String?
    var action: String?
    var decision: String?
    var faultSource: String?
    var refundAmountPaise: Int?
    var returnPackageCount: Int?
    var correctedAddress: Address?

    var valid: Bool {
        // Reject cross-operation fields as well as malformed required values, including restored journals.
        let populated = Set(encodedFields.keys)
        let base: Set<String> = ["operation"]
        let common: Set<String> = ["expectedVersion", "reason"]
        let allowed: Set<String>
        let reasonLength = reason?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        let version = (expectedVersion ?? 0) > 0
        switch operation {
        case .offer:
            allowed = base.union(["recoveryCaseId", "branchId", "expectedVersion"])
            guard recoveryCaseId != nil, branchId != nil, version else { return false }
        case .fail:
            allowed = base.union(common).union(["recoveryCaseId"])
            guard recoveryCaseId != nil, version, (3...500).contains(reasonLength) else { return false }
        case .delivery:
            allowed = base.union(common).union(["recoveryCaseId", "action", "faultSource", "refundAmountPaise", "correctedAddress"])
            guard recoveryCaseId != nil, version, (10...500).contains(reasonLength), ["RIDER", "MERCHANT", "DASTAK", "CUSTOMER"].contains(faultSource ?? ""), ["RESUME_DELIVERY", "RETURN_TO_ORIGIN"].contains(action ?? "") else { return false }
            guard correctedAddress == nil || (action == "RESUME_DELIVERY" && correctedAddress?.valid == true), refundAmountPaise == nil || (action == "RETURN_TO_ORIGIN" && faultSource != "CUSTOMER" && refundAmountPaise! > 0) else { return false }
        case .issue:
            allowed = base.union(common).union(["issueId", "decision", "faultSource", "refundAmountPaise", "returnPackageCount"])
            guard issueId != nil, version, (3...500).contains(reasonLength), ["REJECT", "RESOLVE_NO_REFUND", "REFUND_WITHOUT_RETURN", "PHYSICAL_RETURN"].contains(decision ?? "") else { return false }
            if ["PHYSICAL_RETURN", "REFUND_WITHOUT_RETURN"].contains(decision ?? "") {
                guard (refundAmountPaise ?? 0) > 0, ["UNKNOWN", "MERCHANT", "RIDER", "DASTAK", "CUSTOMER", "NONE"].contains(faultSource ?? "") else { return false }
                guard decision == "PHYSICAL_RETURN" ? (1...1000).contains(returnPackageCount ?? 0) : returnPackageCount == nil else { return false }
            } else if refundAmountPaise != nil || faultSource != nil || returnPackageCount != nil { return false }
        case .rider:
            allowed = base.union(["returnMissionId", "riderId", "expectedVersion"])
            guard returnMissionId != nil, riderId != nil, version else { return false }
        case .refund:
            allowed = base.union(["entityType", "orderId", "refundId"])
            guard entityType == "dastak_v1_order", orderId != nil, refundId != nil else { return false }
        case .settlement:
            allowed = base.union(["settlementEntryId", "expectedVersion"])
            guard settlementEntryId != nil, version else { return false }
        case .handoff:
            allowed = base.union(["missionId", "deliveryEvidenceId", "reason", "expectedMissionVersion"])
            guard missionId != nil, deliveryEvidenceId != nil, (expectedMissionVersion ?? 0) > 0, (10...500).contains(reasonLength) else { return false }
        case .cancel:
            allowed = base.union(common).union(["orderId"])
            guard orderId != nil, version, (10...500).contains(reasonLength) else { return false }
        }
        return populated.isSubset(of: allowed)
    }
    var encodedFields: [String: DastakAdminTraceValue] {
        guard let data = try? JSONEncoder().encode(self), let record = try? JSONDecoder().decode(DastakAdminTraceRecord.self, from: data) else { return [:] }
        return record.fields
    }
}

struct DastakAdminExecutionCommand: Codable, Equatable, Sendable {
    var formatVersion = 1
    let accountID: UUID
    let orderID: UUID
    let key: IdempotencyKey
    let request: DastakAdminExecutionRequest
    var relatedMissionID: UUID?
    var currency: String?
    var approvedAmountPaise: Int?
    var revision = UUID()
    var acknowledged = false
    var valid: Bool { formatVersion == 1 && UUID(uuidString: key.rawValue) != nil && request.valid && (request.orderId == nil || request.orderId == orderID) && (request.operation != .delivery || relatedMissionID != nil) && (![DastakAdminExecutionAction.settlement, .refund].contains(request.operation) || currency?.isEmpty == false) && (request.operation != .refund || (approvedAmountPaise ?? 0) > 0) }
}

protocol DastakAdminExecutionStorage: Sendable {
    func load(_ accountID: UUID) async throws -> DastakAdminExecutionCommand?
    func replace(_ command: DastakAdminExecutionCommand?, accountID: UUID, expectedRevision: UUID?) async throws
}
enum DastakAdminExecutionError: Error { case invalid, changed }
actor DastakAdminExecutionFileStore: DastakAdminExecutionStorage {
    static let shared = DastakAdminExecutionFileStore()
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("DastakAdminExecutionCommands", isDirectory: true)) { self.directory = directory }
    func load(_ id: UUID) throws -> DastakAdminExecutionCommand? {
        let url = file(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 32_768 else { throw DastakAdminExecutionError.invalid }
        let command = try JSONDecoder().decode(DastakAdminExecutionCommand.self, from: Data(contentsOf: url))
        guard command.accountID == id, command.valid else { throw DastakAdminExecutionError.invalid }
        return command
    }
    func replace(_ command: DastakAdminExecutionCommand?, accountID: UUID, expectedRevision: UUID?) throws {
        guard try load(accountID)?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        let url = file(accountID)
        guard let command else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        guard command.valid, command.accountID == accountID else { throw DastakAdminExecutionError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directoryURL = directory
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directoryURL.setResourceValues(attributes)
        #if os(iOS)
        try JSONEncoder().encode(command).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try JSONEncoder().encode(command).write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
}
