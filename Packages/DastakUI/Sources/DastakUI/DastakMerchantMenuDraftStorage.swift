import Foundation

struct DastakMerchantMenuDraftArchive: Codable {
    var formatVersion = 1
    var revision = UUID()
    let accountID: UUID
    let branchID: UUID
    let records: [UUID: DastakMerchantMenuDraft]
    let additions: [UUID: DastakMerchantMenuAddition]
    let composer: DastakMerchantMenuComposer
    var valid: Bool {
        formatVersion == 1 && records.count<=2_000 && additions.count<=2_000
            && records.allSatisfy { id, draft in
                id == draft.baseline.id && draft.baseline.version>0 && draft.baseline.mediaVersion>=0
                    && (draft.latest == nil || (draft.latest?.id == id && draft.latest?.payload.entityType == draft.baseline.payload.entityType))
            }
    }
}

@MainActor protocol DastakMerchantMenuDraftStorage {
    func load(account: UUID, branch: UUID) throws -> DastakMerchantMenuDraftArchive?
    func replace(_ archive: DastakMerchantMenuDraftArchive, expectedRevision: UUID?) throws
    func discard(account: UUID, branch: UUID) throws
}

/// Merchant-only device storage. Never placed in a shared app-group container,
/// uploaded, or used as an authority to send a command without a fresh menu.
@MainActor final class DastakMerchantMenuFileDraftStorage: DastakMerchantMenuDraftStorage {
    static let shared = DastakMerchantMenuFileDraftStorage()
    private let directory: URL
    private let maximumBytes = 2 * 1_024 * 1_024
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("DastakMerchantMenuDrafts",isDirectory: true)) { self.directory = directory }
    func load(account: UUID, branch: UUID) throws -> DastakMerchantMenuDraftArchive? {
        let url = file(account,branch)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max)<=maximumBytes else { throw DastakAdminExecutionError.invalid }
        let archive = try JSONDecoder().decode(DastakMerchantMenuDraftArchive.self,from: Data(contentsOf: url))
        guard archive.valid, archive.accountID == account, archive.branchID == branch else { throw DastakAdminExecutionError.invalid }
        return archive
    }
    func replace(_ archive: DastakMerchantMenuDraftArchive, expectedRevision: UUID?) throws {
        guard archive.valid, try load(account: archive.accountID,branch: archive.branchID)?.revision == expectedRevision else { throw DastakAdminExecutionError.changed }
        let data = try JSONEncoder().encode(archive)
        guard data.count<=maximumBytes else { throw DastakAdminExecutionError.invalid }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        var url = directory; var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try url.setResourceValues(attributes)
        let destination = file(archive.accountID,archive.branchID)
        #if os(iOS)
        try data.write(to: destination,options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: destination,options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: destination.path)
    }
    func discard(account: UUID, branch: UUID) throws {
        let url = file(account,branch)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func file(_ account: UUID,_ branch: UUID) -> URL {
        directory.appendingPathComponent(account.uuidString.lowercased()+"-"+branch.uuidString.lowercased()+".json")
    }
}
