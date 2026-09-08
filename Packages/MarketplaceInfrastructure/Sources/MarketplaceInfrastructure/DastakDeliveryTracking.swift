import Foundation

/// A mission-scoped last-known fix, never a route history. The server stops
/// exposing this projection on completion or loss of order/branch access.
public struct DastakDeliveryTracking: Codable, Equatable, Sendable {
    public let missionId: UUID
    public let phase: String
    public let riderName: String
    public let transportType: String?
    public let location: DastakV1Coordinate?
    public let recordedAt: String?
    public let receivedAt: String?
    public let liveUntil: String?
    public let accuracyMeters: Double?
    public let sequence: Int?
    public let serverTime: String

    public func isLive(at date: Date = .now) -> Bool {
        guard location != nil, let accuracyMeters, accuracyMeters >= 0, accuracyMeters <= 35,
              let until = Self.date(liveUntil), let recorded = Self.date(recordedAt) else { return false }
        return date < until && recorded <= date.addingTimeInterval(5)
    }

    public static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct DastakArrivalEligibility: Codable, Equatable, Sendable {
    public let eligible: Bool
    public let reason: String
    public let distanceMeters: Double?
    public let radiusMeters: Int
    public let validUntil: String?

    public func canArrive(at date: Date = .now) -> Bool {
        eligible && (DastakDeliveryTracking.date(validUntil).map { $0 > date } ?? false)
    }
}

public struct DastakMissionLocationSample: Encodable, Sendable {
    public let operation = "v1PublishLocation"
    public let missionId: UUID
    public let latitude: Double
    public let longitude: Double
    public let accuracyMeters: Double
    public let recordedAt: String

    public init(missionId: UUID, latitude: Double, longitude: Double, accuracyMeters: Double, recordedAt: Date) {
        self.missionId = missionId
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.recordedAt = formatter.string(from: recordedAt)
    }
}
