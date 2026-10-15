import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakDeliveryCommand: Codable, Equatable, Sendable {
    var formatVersion = 1
    enum Operation: String, Codable, Sendable {
        case arriveCustomer = "v1ReturnArriveAtCustomer"
        case evidence = "v1AddReturnEvidence"
        case pickup = "v1VerifyReturnPickup"
        case arriveStop = "v1ArriveAtReturnStop"
        case receipt = "v1VerifyReturnReceipt"
        case problem = "v1ReportDeliveryProblem"
        case unreachable = "v1ReportCustomerUnreachable"
        case accept = "v1AcceptOffer"
        case decline = "v1DeclineOffer"
        case start = "v1StartPickups"
        case arrivePickup = "v1ArriveAtPickup"
        case verifyPickup = "v1VerifyPickup"
        case startFinal = "v1StartFinalDelivery"
        case arriveDelivery = "v1ArriveAtCustomer"
        case verifyPIN = "v1VerifyCustomerPIN"
        case deliveryEvidence = "v1AddDeliveryEvidence"
        case complete = "v1CompleteDelivery"
        case verifyDelivery = "v1VerifyDelivery"
        case cancel = "v1CancelBeforePickup"
        case collection = "v1RecordLaunchCollection"
        case legacyDelivery = "legacyDelivery"
        case parcelDelivery = "parcelDelivery"
        var isReturn: Bool { [.arriveCustomer, .evidence, .pickup, .arriveStop, .receipt].contains(self) }
        var isProblem: Bool { self == .problem || self == .unreachable }
        var isOffer: Bool { self == .accept || self == .decline }
        var hasPhoto: Bool { self == .evidence || self == .deliveryEvidence }
        var isAssignment: Bool { self == .legacyDelivery || self == .parcelDelivery }
    }
    let accountID: UUID
    var revision = UUID()
    let key: IdempotencyKey
    let operation: Operation
    let missionID: UUID
    let expectedVersion: Int
    let stopID: UUID?
    let code: String?
    let reason: String?
    let objectPath: String?
    var photo: Data?
    let contentType: String?
    var uploaded = false
    var acknowledged = false
    var offerID: UUID? = nil
    var packageCount: Int? = nil
    var outcome: DastakV1CollectionOutcome? = nil
    var method: DastakV1CollectionMethod? = nil
    var collectionReference: String? = nil
    var failureReason: String? = nil
    var assignmentAction: String? = nil
    var isValid: Bool {
        formatVersion == 1 && expectedVersion > 0 && UUID(uuidString: key.rawValue) != nil
            && (photo?.count ?? 0) <= 10 * 1_024 * 1_024
            && (!operation.hasPhoto || (objectPath?.hasPrefix("\(operation == .evidence ? "return-pickup" : "rider-delivery")/\(accountID.uuidString.lowercased())/") == true
                && ["image/jpeg", "image/png", "image/heic"].contains(contentType ?? "")
                && (uploaded || !(photo?.isEmpty ?? true))))
            && (![Operation.pickup, .receipt, .verifyPickup, .verifyPIN, .verifyDelivery].contains(operation) ||
                (code?.count == 6 && code?.allSatisfy { $0.isASCII && $0.isNumber } == true))
            && (![Operation.arriveStop, .receipt, .arrivePickup, .verifyPickup].contains(operation) || stopID != nil)
            && (!operation.isProblem || (3...500).contains(reason?.count ?? 0))
            && (!operation.isOffer || offerID != nil)
            && (operation != .verifyPickup || (packageCount ?? 0) > 0)
            && (operation != .collection || (outcome != nil && method != nil))
            && (!operation.isAssignment || (["acceptOffer", "declineOffer", "startToStore", "arriveAtStore", "confirmPickup", "startDelivery", "completeDelivery", "acknowledgeAssignment", "declineAssignment", "startToPickup"].contains(assignmentAction ?? "")))
    }
}

protocol DastakDeliveryCommandStorage: Sendable {
    func load(_ accountID: UUID) async throws -> DastakDeliveryCommand?
    func replace(_ command: DastakDeliveryCommand?, accountID: UUID, expectedRevision: UUID?) async throws
}

enum DastakDeliveryJournalError: Error { case invalid, changed }

/// Shared across scenes; compare-and-swap prevents a second workspace overwriting an unresolved handoff.
actor DastakDeliveryCommandFileStore: DastakDeliveryCommandStorage {
    static let shared = DastakDeliveryCommandFileStore()
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("DastakDeliveryCommands", isDirectory: true)) {
        self.directory = directory
    }
    func load(_ accountID: UUID) throws -> DastakDeliveryCommand? {
        let url = file(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 15 * 1_024 * 1_024 else {
            throw DastakDeliveryJournalError.invalid
        }
        let command = try JSONDecoder().decode(DastakDeliveryCommand.self, from: Data(contentsOf: url))
        guard command.accountID == accountID, command.isValid else { throw DastakDeliveryJournalError.invalid }
        return command
    }
    func replace(_ command: DastakDeliveryCommand?, accountID: UUID, expectedRevision: UUID?) throws {
        guard try load(accountID)?.revision == expectedRevision else { throw DastakDeliveryJournalError.changed }
        let url = file(accountID)
        guard let command else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        guard command.accountID == accountID, command.isValid else { throw DastakDeliveryJournalError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directoryURL = directory
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directoryURL.setResourceValues(attributes)
        let data = try JSONEncoder().encode(command)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
}
