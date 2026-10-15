import Foundation

/// A mission-scoped last-known fix, never a route history. The server stops
/// exposing this projection on completion or loss of order/branch access.
public struct DastakDeliveryTracking: Codable, Equatable, Sendable {
    public let missionId: UUID
    public let phase: String
    public let riderName: String
    public let riderPhoneNumber: String?
    public let transportType: String?
    public let location: DastakV1Coordinate?
    public let recordedAt: String?
    public let receivedAt: String?
    public let liveUntil: String?
    public let accuracyMeters: Double?
    public let sequence: Int?
    public let serverTime: String

    private enum CodingKeys: String, CodingKey {
        case missionId, phase, riderName, riderPhoneNumber, transportType, location
        case recordedAt, receivedAt, liveUntil, accuracyMeters, sequence, serverTime
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        missionId = try values.decode(UUID.self, forKey: .missionId)
        phase = try values.decode(String.self, forKey: .phase)
        riderName = try values.decode(String.self, forKey: .riderName)
        let number = try? values.decode(String.self, forKey: .riderPhoneNumber)
        riderPhoneNumber = Self.validPhone(number)
        transportType = try values.decodeIfPresent(String.self, forKey: .transportType)
        location = try values.decodeIfPresent(DastakV1Coordinate.self, forKey: .location)
        recordedAt = try values.decodeIfPresent(String.self, forKey: .recordedAt)
        receivedAt = try values.decodeIfPresent(String.self, forKey: .receivedAt)
        liveUntil = try values.decodeIfPresent(String.self, forKey: .liveUntil)
        accuracyMeters = try values.decodeIfPresent(Double.self, forKey: .accuracyMeters)
        sequence = try values.decodeIfPresent(Int.self, forKey: .sequence)
        serverTime = try values.decode(String.self, forKey: .serverTime)
    }

    /// Contact is independent of GPS freshness, but never outlives the active order/mission.
    public func customerCallURL(orderStatus: String) -> URL? {
        guard ["PAID", "PREPARING", "PICKUP_IN_PROGRESS", "OUT_FOR_DELIVERY"].contains(orderStatus),
              ["ASSIGNED", "EN_ROUTE_TO_PICKUPS", "PICKUP_IN_PROGRESS", "ALL_PACKAGES_PICKED_UP",
               "OUT_FOR_DELIVERY", "ARRIVED", "DELIVERY_RECOVERY"].contains(phase),
              let number = Self.validPhone(riderPhoneNumber) else { return nil }
        return URL(string: "tel:\(number)")
    }

    private static func validPhone(_ number: String?) -> String? {
        guard let number else { return nil }
        let bytes = Array(number.utf8)
        guard (9...16).contains(bytes.count), bytes[0] == 43, (49...57).contains(bytes[1]),
              bytes.dropFirst(2).allSatisfy({ (48...57).contains($0) }) else { return nil }
        return number
    }

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
