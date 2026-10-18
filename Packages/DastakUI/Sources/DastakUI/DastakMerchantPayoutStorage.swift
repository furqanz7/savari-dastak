import Foundation
import Security
import MarketplaceFoundation
import MarketplaceInfrastructure

struct DastakMerchantPayoutCommand: Codable, Equatable, Sendable {
    enum Operation: Codable, Equatable, Sendable {
        case withdraw(amount: Int,destination: UUID,destinationVersion: Int)
        case retry(withdrawal: UUID,version: Int,amount: Int)
        case destination(DastakMerchantDestinationRequest)
    }
    var formatVersion = 1
    let accountID: UUID
    let organizationID: UUID
    let key: IdempotencyKey
    let operation: Operation
    var revision = UUID()
    var attempts = 0
    var acknowledged = false
    var valid: Bool {
        guard formatVersion==1,UUID(uuidString:key.rawValue) != nil,(0..<Int.max).contains(attempts) else { return false }
        switch operation {
        case let .withdraw(amount,_,version),let .retry(_,version,amount): return (1...9_007_199_254_740_991).contains(amount) && version>0 && version<9_007_199_254_740_991
        case let .destination(request): return request.subjectId==organizationID && request.valid
        }
    }
    var summary: String {
        switch operation {
        case let .withdraw(amount,_,_): "Withdrawal · " + DastakFormatting.money(.init(paise:amount))
        case let .retry(_,_,amount): "Existing payout check · " + DastakFormatting.money(.init(paise:amount))
        case let .destination(request): "Destination setup · " + request.maskedLabel
        }
    }
}
protocol DastakMerchantPayoutStorage: Sendable {
    func load(_ account: UUID) async throws -> DastakMerchantPayoutCommand?
    func replace(_ command: DastakMerchantPayoutCommand?,account: UUID,expectedRevision: UUID?) async throws
}
actor DastakMerchantMemoryPayoutStore: DastakMerchantPayoutStorage {
    private var values: [UUID:DastakMerchantPayoutCommand] = [:]
    func load(_ account: UUID) -> DastakMerchantPayoutCommand? { values[account] }
    func replace(_ command: DastakMerchantPayoutCommand?,account: UUID,expectedRevision: UUID?) throws {
        guard values[account]?.revision==expectedRevision,command == nil || (command?.valid==true && command?.accountID==account) else { throw DastakAdminExecutionError.changed }
        values[account] = command
    }
}
/// Default access group of the Merchant app only. Bank/UPI recovery details
/// never enter a file, UserDefaults, an app group, diagnostics, or iCloud sync.
actor DastakMerchantPayoutKeychainStore: DastakMerchantPayoutStorage {
    static let shared = DastakMerchantPayoutKeychainStore()
    private let service: String
    init(service: String = "com.dastak.merchant.payout-recovery.v1") { self.service = service }
    private func query(_ account: UUID) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
         kSecAttrAccount as String:account.uuidString.lowercased(),kSecAttrSynchronizable as String:false,
         kSecUseAuthenticationUI as String:kSecUseAuthenticationUIFail]
    }
    func load(_ account: UUID) throws -> DastakMerchantPayoutCommand? {
        var request = query(account); request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,let data = result as? Data,data.count<=16_384 else { throw DastakAdminExecutionError.invalid }
        let value = try JSONDecoder().decode(DastakMerchantPayoutCommand.self,from:data)
        guard value.valid,value.accountID==account else { throw DastakAdminExecutionError.invalid }
        return value
    }
    func replace(_ command: DastakMerchantPayoutCommand?,account: UUID,expectedRevision: UUID?) throws {
        guard try load(account)?.revision==expectedRevision else { throw DastakAdminExecutionError.changed }
        guard let command else {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw DastakAdminExecutionError.changed }
            return
        }
        guard command.valid,command.accountID==account else { throw DastakAdminExecutionError.invalid }
        let data = try JSONEncoder().encode(command)
        guard data.count<=16_384 else { throw DastakAdminExecutionError.invalid }
        if expectedRevision == nil {
            var request = query(account); request[kSecValueData as String] = data
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(request as CFDictionary,nil)==errSecSuccess else { throw DastakAdminExecutionError.changed }
        } else {
            guard SecItemUpdate(query(account) as CFDictionary,[kSecValueData as String:data] as CFDictionary)==errSecSuccess else { throw DastakAdminExecutionError.changed }
        }
    }
}

enum DastakMerchantPayoutAmount {
    static func paise(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard text.range(of:"^[0-9]{1,14}(\\.[0-9]{1,2})?$",options:.regularExpression) != nil,
              let value = Decimal(string:text),value>0,value*100<=Decimal(9_007_199_254_740_991 as Int64) else { return nil }
        return NSDecimalNumber(decimal:value*100).intValue
    }
}
