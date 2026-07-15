public struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        precondition((-90...90).contains(latitude))
        precondition((-180...180).contains(longitude))
        self.latitude = latitude
        self.longitude = longitude
    }
}
