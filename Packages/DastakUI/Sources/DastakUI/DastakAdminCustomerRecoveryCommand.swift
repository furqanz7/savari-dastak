import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakAdminCustomerRecoveryCommand: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable { case sessions, phone }
    var formatVersion = 1
    let actorID: UUID
    let accountID: UUID
    let action: Action
    let scope: String?
    let sessionID: UUID?
    let currentPhone: String?
    let replacementPhone: String?
    let claimVersion: Int?
    let reason: String
    let key: IdempotencyKey
    var revision = UUID()
    var attempts = 0
    var acknowledged = false
    var valid: Bool {
        guard formatVersion == 1, UUID(uuidString: key.rawValue) != nil, (0..<Int.max).contains(attempts), reason == reason.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        switch action {
        case .sessions: return (3...200).contains(reason.count) && ["SINGLE", "ALL"].contains(scope ?? "") && (scope == "SINGLE" ? sessionID != nil : sessionID == nil) && currentPhone == nil && replacementPhone == nil && claimVersion == nil
        case .phone: return (3...500).contains(reason.count) && scope == nil && sessionID == nil && currentPhone.map(DastakAdminCustomerRecoveryContract.phone) == true && replacementPhone.map(DastakAdminCustomerRecoveryContract.phone) == true && currentPhone != replacementPhone && (1..<9_007_199_254_740_991).contains(claimVersion ?? 0)
        }
    }
}
protocol DastakAdminCustomerRecoveryStorage: Sendable {
    func load(_ actorID: UUID) async throws -> DastakAdminCustomerRecoveryCommand?
    func replace(_ command: DastakAdminCustomerRecoveryCommand?, actorID: UUID, expectedRevision: UUID?) async throws
}
actor DastakAdminCustomerRecoveryFileStore: DastakAdminCustomerRecoveryStorage {
    static let shared = DastakAdminCustomerRecoveryFileStore()
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("DastakAdminCustomerRecovery", isDirectory: true)) { self.directory = directory }
    func load(_ actorID: UUID) throws -> DastakAdminCustomerRecoveryCommand? {
        let url = file(actorID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 16_384 else { throw DastakAdminExecutionError.invalid }
        let command = try JSONDecoder().decode(DastakAdminCustomerRecoveryCommand.self, from: Data(contentsOf: url))
        guard command.actorID == actorID, command.valid else { throw DastakAdminExecutionError.invalid }
        return command
    }
    func replace(_ command: DastakAdminCustomerRecoveryCommand?, actorID: UUID, expectedRevision: UUID?) throws {
        guard try load(actorID)?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        let url = file(actorID)
        guard let command else { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }; return }
        guard command.actorID == actorID, command.valid else { throw DastakAdminExecutionError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directoryURL = directory; var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directoryURL.setResourceValues(attributes)
        #if os(iOS)
        try JSONEncoder().encode(command).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try JSONEncoder().encode(command).write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func file(_ actorID: UUID) -> URL { directory.appendingPathComponent(actorID.uuidString.lowercased() + ".json") }
}
