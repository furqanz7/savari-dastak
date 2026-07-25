import Foundation
import MarketplaceFoundation

public struct Parcel: Codable, Equatable, Sendable {
    public let parcelID: UUID
    public let declaredContents: String
    public let declaredValue: Money

    public init(
        parcelID: UUID,
        declaredContents: String,
        declaredValue: Money
    ) {
        self.parcelID = parcelID
        self.declaredContents = declaredContents
        self.declaredValue = declaredValue
    }

    private enum CodingKeys: String, CodingKey {
        case parcelID = "parcelId"
        case declaredContents
        case declaredValue
    }
}

public struct ParcelRecipient: Codable, Equatable, Sendable {
    public let displayName: String
    public let phoneNumber: String

    public init(displayName: String, phoneNumber: String) {
        self.displayName = displayName
        self.phoneNumber = phoneNumber
    }
}
