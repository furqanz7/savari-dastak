import Foundation

public struct E164PhoneNumber: Equatable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let bytes = Array(rawValue.utf8)
        guard
            (9...16).contains(bytes.count),
            bytes.first == 43,
            (49...57).contains(bytes[1]),
            bytes.dropFirst().allSatisfy({ (48...57).contains($0) })
        else {
            throw AuthenticationClientError.invalidE164PhoneNumber
        }
        self.rawValue = rawValue
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
