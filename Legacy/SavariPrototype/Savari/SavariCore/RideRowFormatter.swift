import Foundation

enum RideRowFormatter {
    static func fareString(for ride: [String: Any]) -> String {
        if let cancellationFare = doubleValue(ride["cancellation_fare"]) {
            return String(format: "%.2f", cancellationFare)
        }
        if let fare = doubleValue(ride["fare"]) {
            return String(format: "%.2f", fare)
        }
        if let estimatedFare = doubleValue(ride["estimated_fare"]) {
            return String(format: "%.2f", estimatedFare)
        }
        return String(format: "%.2f", 0.0)
    }

    static func shortId(_ ride: [String: Any]) -> String {
        guard let id = ride["id"] as? String, !id.isEmpty else { return "NEW" }
        return String(id.prefix(8)).uppercased()
    }

    static func vehicleType(for ride: [String: Any]) -> String {
        (ride["vehicle_type"] as? String) ?? "Ride"
    }

    static func distanceString(for ride: [String: Any]) -> String {
        let meters = doubleValue(ride["estimated_distance_m"])
            ?? doubleValue(ride["estimated_distance_meters"])
        guard let meters, meters > 0 else {
            return "Distance pending"
        }
        return String(format: "%.1f km", meters / 1000.0)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
