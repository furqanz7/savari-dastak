import Foundation

public struct E164PhoneNumber: Equatable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard let canonical = DastakPhoneNumberValidator.canonicalE164(rawValue) else {
            throw AuthenticationClientError.invalidE164PhoneNumber
        }
        self.rawValue = canonical
    }
}

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
