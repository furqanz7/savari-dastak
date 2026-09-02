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

struct AccountBootstrapResult: Decodable, Equatable, Sendable {
    let accountID: UUID
    let phoneRecorded: Bool

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"
        case phoneRecorded
    }
}

struct AccountBootstrapRequest: Encodable, Sendable {
    let application: String
    let displayName: String
    let phoneNumber: String
}
