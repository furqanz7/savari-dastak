import Foundation

struct DastakMerchantJournalRecord: Codable, Equatable, Sendable {
    enum Command: Codable, Equatable, Sendable {
        case recovery(DastakMerchantRecoveryCommand)
        case restaurant(DastakMerchantRestaurantCommand)
        case operation(DastakMerchantOperationCommand)
        var valid: Bool { switch self { case let .recovery(value): value.valid; case let .restaurant(value): value.valid; case let .operation(value): value.valid } }
    }
    var formatVersion = 1
    let accountID: UUID
    let command: Command
    var revision = UUID()
    var attempts = 0
    var acknowledged = false
    // Optional for backwards compatibility with existing protected journals.
    var uploadCompleted: Bool?
    var valid: Bool {
        guard formatVersion == 1 && (0..<Int.max).contains(attempts) && command.valid else { return false }
        if case let .operation(value) = command, let upload = value.upload {
            let owner = accountID.uuidString.lowercased()
            return upload.path.hasPrefix(upload.bucket == "dastak-evidence" ? "merchant-ready/\(owner)/" : "merchant/\(owner)/")
        }
        return true
    }
}
protocol DastakMerchantJournalStorage: Sendable {
    func load(_ accountID: UUID) async throws -> DastakMerchantJournalRecord?
    func replace(_ record: DastakMerchantJournalRecord?, accountID: UUID, expectedRevision: UUID?) async throws
}
actor DastakMerchantMemoryJournal: DastakMerchantJournalStorage {
    private var records: [UUID: DastakMerchantJournalRecord] = [:]
    func load(_ accountID: UUID) -> DastakMerchantJournalRecord? { records[accountID] }
    func replace(_ record: DastakMerchantJournalRecord?, accountID: UUID, expectedRevision: UUID?) throws {
        guard records[accountID]?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        guard record == nil || (record?.valid == true && record?.accountID == accountID) else { throw DastakAdminExecutionError.invalid }
        records[accountID] = record
    }
}
actor DastakMerchantFileJournal: DastakMerchantJournalStorage {
    static let shared = DastakMerchantFileJournal()
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("DastakMerchantCommands", isDirectory: true)) { self.directory = directory }
    func load(_ accountID: UUID) throws -> DastakMerchantJournalRecord? {
        let url = file(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 16 * 1_024 * 1_024 else { throw DastakAdminExecutionError.invalid }
        let record = try JSONDecoder().decode(DastakMerchantJournalRecord.self, from: Data(contentsOf: url))
        guard record.accountID == accountID && record.valid else { throw DastakAdminExecutionError.invalid }
        return record
    }
    func replace(_ record: DastakMerchantJournalRecord?, accountID: UUID, expectedRevision: UUID?) throws {
        guard try load(accountID)?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        let url = file(accountID)
        guard let record else { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }; return }
        guard record.valid, record.accountID == accountID else { throw DastakAdminExecutionError.invalid }
        let data = try JSONEncoder().encode(record)
        guard data.count <= 16 * 1_024 * 1_024 else { throw DastakAdminExecutionError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var directoryURL = directory; var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directoryURL.setResourceValues(attributes)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
}
