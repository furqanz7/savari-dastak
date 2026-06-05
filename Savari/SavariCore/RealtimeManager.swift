import Foundation

func realtimeUUIDStringsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs, let rhs else { return false }
    if let leftUUID = UUID(uuidString: lhs), let rightUUID = UUID(uuidString: rhs) {
        return leftUUID == rightUUID
    }
    return lhs.caseInsensitiveCompare(rhs) == .orderedSame
}

nonisolated final class RealtimeManager {
    static let shared = RealtimeManager()
    private init() {}

    var pollingTask: Task<Void, Never>?
    let pollingInterval: TimeInterval = 2.0

    static func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func jsonArray(from data: Data) -> [[String: Any]]? {
        try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    nonisolated struct RideRow: Codable, Sendable {
        let id: String
        let driver_id: String?
        let assigned_driver_id: String?
        let passenger_id: String?
        let pickup_lat: Double?
        let pickup_lon: Double?
        let drop_lat: Double?
        let drop_lon: Double?
        let dest_lat: Double?
        let dest_lon: Double?
        let boarding_code: String?
        let status: String?

        var pickupLatValue: Double? { pickup_lat }
        var pickupLonValue: Double? { pickup_lon }
        var dropLatValue: Double? { drop_lat ?? dest_lat }
        var dropLonValue: Double? { drop_lon ?? dest_lon }
    }

    nonisolated struct DriverRow: Codable, Sendable {
        let id: String?
        let driver_id: String
        let latitude: Double
        let longitude: Double
    }
}
