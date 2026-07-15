import Foundation

enum PhoneVerificationState: String, Codable, Sendable {
    case unverified
    case verified
}

struct AccountBootstrapResult: Decodable, Equatable, Sendable {
    let accountID: UUID
    let phoneState: PhoneVerificationState

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"
        case phoneState
    }
}

struct AccountBootstrapRequest: Encodable, Sendable {
    let displayName: String
    let phoneNumber: String
}
