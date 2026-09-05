public enum DeliveryMethod: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case retired
    case walking
    case bicycle
    case bike
    case auto

    public static let allCases: [DeliveryMethod] = [.walking, .bicycle, .bike, .auto]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let method = DeliveryMethod(rawValue: value) {
            self = method
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown parcel delivery method."
            )
        }
    }
}
