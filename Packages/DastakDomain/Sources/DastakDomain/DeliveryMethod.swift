public enum DeliveryMethod: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case retired
    case bike
    case auto

    public static let allCases: [DeliveryMethod] = [.bike, .auto]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "walking" || value == "bicycle" {
            self = .retired
        } else if let method = DeliveryMethod(rawValue: value) {
            self = method
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown parcel delivery method."
            )
        }
    }
}
