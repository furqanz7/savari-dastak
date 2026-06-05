import SwiftUI
@preconcurrency import Foundation
import MapKit
import Combine
import Supabase
import CoreLocation
import Realtime

private func realtimeUUIDStringsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs, let rhs else { return false }
    if let leftUUID = UUID(uuidString: lhs), let rightUUID = UUID(uuidString: rhs) {
        return leftUUID == rightUUID
    }
    return lhs.caseInsensitiveCompare(rhs) == .orderedSame
}

nonisolated final class RealtimeManager {
    static let shared = RealtimeManager()
    private init() {}

    private var pollingTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 2.0

    private static func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func jsonArray(from data: Data) -> [[String: Any]]? {
        try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }
    
    nonisolated fileprivate struct RideRow: Codable, Sendable {
        // accept both possible driver column names
        let id: String
        let driver_id: String?            // DB may use `driver_id`
        let assigned_driver_id: String?   // some RPCs may write `assigned_driver_id`
        let passenger_id: String?
        // pickup
        let pickup_lat: Double?
        let pickup_lon: Double?
        // destination — accept either naming conventions
        let drop_lat: Double?     // DB final column
        let drop_lon: Double?     // DB final column
        let dest_lat: Double?     // older field name used by client
        let dest_lon: Double?     // older field name used by client
        let boarding_code: String?
        let status: String?
        
        // helper to normalize pickup/dest access:
        var pickupLatValue: Double? { pickup_lat ?? nil }
        var pickupLonValue: Double? { pickup_lon ?? nil }
        var dropLatValue: Double? { drop_lat ?? dest_lat }
        var dropLonValue: Double? { drop_lon ?? dest_lon }
    }
    
    // MARK: - DriverRow (for realtime decoding)
    nonisolated fileprivate struct DriverRow: Codable, Sendable {
        let id: String?              // sometimes present
        let driver_id: String        // required
        let latitude: Double
        let longitude: Double
    }

    func subscribeDriverLocations(onUpdate: @escaping ([Driver]) -> Void) async -> () -> Void {
        let realtimeV2 = await MainActor.run { SupabaseManager.shared.client.realtimeV2 }
        do {
            let channel = realtimeV2.channel("public:driver_locations")
            let decoder = JSONDecoder()

            let streamTask = Task.detached {
                do {
                    for try await change in channel.postgresChange(AnyAction.self, table: "driver_locations") {
                        switch change {
                        case .insert(let insertion):
                            // pass decoder explicitly
                            let row = try insertion.decodeRecord(as: DriverRow.self, decoder: decoder)
                            if let uuid = UUID(uuidString: row.driver_id) {
                                let d = Driver(id: uuid,
                                               coordinate: CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude),
                                               name: "Driver",
                                               color: .blue)
                                await MainActor.run { onUpdate([d]) }
                            }
                        case .update(let update):
                            let row = try update.decodeRecord(as: DriverRow.self, decoder: decoder)
                            if let uuid = UUID(uuidString: row.driver_id) {
                                let d = Driver(id: uuid,
                                               coordinate: CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude),
                                               name: "Driver",
                                               color: .blue)
                                await MainActor.run { onUpdate([d]) }
                            }
                        case .delete(let deletion):
                            let old = try deletion.decodeOldRecord(as: DriverRow.self, decoder: decoder)
                            if let uuid = UUID(uuidString: old.driver_id) {
                                let d = Driver(id: uuid,
                                               coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                               name: "Driver",
                                               color: .blue)
                                await MainActor.run { onUpdate([d]) }
                            }
                        }
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] realtime driver_locations stream ended:", error)
                }
            }

            try await channel.subscribeWithError()
            return {
                Task { @MainActor in
                    streamTask.cancel()
                    await channel.unsubscribe()
                }
            }
        } catch {
            SavariLog.debug("[RealtimeManager] Realtime subscribe using SDK failed — falling back to polling:", error)
        }

        // Polling fallback (your existing polling code)
        pollingTask?.cancel()
        pollingTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.fetchDriverLocationsOnce(onUpdate: onUpdate)
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }

        return { [weak self] in
            self?.pollingTask?.cancel()
            self?.pollingTask = nil
        }
    }

    // MARK: - Helpers

    private func fetchDriverLocationsOnce(onUpdate: @escaping ([Driver]) -> Void) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("driver_locations")
                .select()
                .execute()

            if let arr = Self.jsonArray(from: response.data) {
                await MainActor.run { onUpdate(parseDriverRows(arr)) }
                return
            }

            if let dict = Self.jsonObject(from: response.data) {
                if let inner = dict["data"] as? [[String: Any]] {
                    await MainActor.run { onUpdate(parseDriverRows(inner)) }
                    return
                }
            }
        } catch {
            SavariLog.debug("[RealtimeManager] polling fetch error:", error.localizedDescription)
        }
    }

    private func parseDriverRows(_ rows: [[String: Any]]) -> [Driver] {
        var drivers: [Driver] = []
        for row in rows {
            if let idStr = row["driver_id"] as? String,
               let lat = row["latitude"] as? Double,
               let lon = row["longitude"] as? Double {
                let uuid = UUID(uuidString: idStr) ?? UUID()
                let name = "Driver"
                drivers.append(Driver(id: uuid, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), name: name, color: .blue))
            }
        }
        return drivers
    }
    // inside RealtimeManager class

    // MARK: - Ride requests subscription
    func subscribeRideRequests(onUpdate: @escaping ([String:Any]) -> Void) async -> () -> Void {
        let realtimeV2 = await MainActor.run { SupabaseManager.shared.client.realtimeV2 }
        do {
            SavariLog.debug("[RealtimeManager] attempting SDK subscribe to rides")
            let channel = realtimeV2.channel("public:rides")
            let decoder = JSONDecoder()

            let streamTask = Task.detached {
                do {
                    for try await change in channel.postgresChange(AnyAction.self, table: "rides") {
                        switch change {
                        case .insert(let insertion):
                            if let row = try? insertion.decodeRecord(as: RideRow.self, decoder: decoder) {
                                SavariLog.debug("[RealtimeManager][SDK DEBUG] change payload:", insertion.record)
                                    var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String:Any] ?? [:]
                                    // normalize: copy dest_* into drop_* if needed
                                    if dict["drop_lat"] == nil, let dlat = dict["dest_lat"] { dict["drop_lat"] = dlat }
                                    if dict["drop_lon"] == nil, let dlon = dict["dest_lon"] { dict["drop_lon"] = dlon }
                                    let payload = dict
                                    await MainActor.run { onUpdate(["new": payload]) }
                                } else {
                                    // fallback to raw payload dictionary if decode fails
                                    let rawPayload = insertion.record
                                    do {
                                        let data = try JSONSerialization.data(withJSONObject: rawPayload)
                                        var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                                        if dict["drop_lat"] == nil, let dlat = dict["dest_lat"] { dict["drop_lat"] = dlat }
                                        if dict["drop_lon"] == nil, let dlon = dict["dest_lon"] { dict["drop_lon"] = dlon }
                                        let payload = dict
                                        await MainActor.run { onUpdate(["new": payload]) }
                                    } catch {
                                        SavariLog.debug("[RealtimeManager][SDK] unable to normalize insert payload:", error)
                                    }
                                }
                        case .update(let update):
                            let newRow = try update.decodeRecord(as: RideRow.self, decoder: decoder)
                            let oldRow = try? update.decodeOldRecord(as: RideRow.self, decoder: decoder)
                            var payload: [String:Any] = [:]
                            if let data = try? JSONEncoder().encode(newRow),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                                payload["new"] = dict
                            }
                            if let old = oldRow, let oldData = try? JSONEncoder().encode(old),
                               let oldDict = try? JSONSerialization.jsonObject(with: oldData) as? [String:Any] {
                                payload["old"] = oldDict
                            }
                            let updatePayload = payload
                            await MainActor.run { onUpdate(updatePayload) }
                        case .delete(let deletion):
                            let old = try deletion.decodeOldRecord(as: RideRow.self, decoder: decoder)
                            if let data = try? JSONEncoder().encode(old),
                               let dict = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                                SavariLog.debug("[RealtimeManager][SDK] delete:", dict["id"] ?? "(no id)")
                                await MainActor.run { onUpdate(["old": dict]) }
                            }
                        }
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] realtime rides stream ended:", error)
                }
            }

            try await channel.subscribeWithError()
            SavariLog.debug("[RealtimeManager] SDK subscribeWithError succeeded for rides")
            return {
                Task {
                    streamTask.cancel()
                    await channel.unsubscribe()
                }
            }
        } catch {
            SavariLog.debug("[RealtimeManager] subscribeRideRequests via SDK failed:", error)
            SavariLog.debug("[RealtimeManager] falling back to polling for rides")
        }

        // fallback polling (unchanged)
        var pollingTaskLocal: Task<Void, Never>?
        pollingTaskLocal = Task.detached { [weak self] in
            guard let self = self else { return }
            var seen = Set<String>()
            while !Task.isCancelled {
                do {
                    SavariLog.debug("[RealtimeManager][polling] querying rides...")
                    let resp = try await SupabaseManager.shared.client.from("rides").select().execute()
                    if let rows = Self.jsonArray(from: resp.data) {
                        SavariLog.debug("[RealtimeManager][polling] found \(rows.count) rows")
                        for row in rows {
                            if let id = row["id"] as? String, !seen.contains(id) {
                                seen.insert(id)
                                SavariLog.debug("[RealtimeManager][polling] new ride id:", id, "status:", row["status"] ?? "nil")
                                await MainActor.run { onUpdate(["new": row]) }
                            }
                        }
                    } else {
                        SavariLog.debug("[RealtimeManager][polling] response.data not [[String:Any]]; raw:", resp.data)
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] ride polling error:", error)
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }

        return {
            pollingTaskLocal?.cancel()
        }
    }

    // fallback polling helper (private)
    private func startPollingRides(onRideUpdate: @escaping ([String:Any]) -> Void) async -> () -> Void {
        pollingTask?.cancel()
        pollingTask = Task.detached { [weak self] in
            guard self != nil else { return }
            while !Task.isCancelled {
                // get only requested rides
                do {
                    let resp = try await SupabaseManager.shared.client
                        .from("rides")
                        .select()
                        .eq("status", value: "requested")
                        .execute()
                    if let arr = Self.jsonArray(from: resp.data) {
                        for row in arr { await MainActor.run { onRideUpdate(row) } }
                    }
                } catch {
                    SavariLog.debug("polling rides error:", error)
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        return { [weak self] in self?.pollingTask?.cancel(); self?.pollingTask = nil }
    }
}

// --- Additions to RealtimeManager ---
extension RealtimeManager {
    // --- single-driver subscription (fixed)
    func subscribeDriverLocation(driverId: String, onUpdate: @escaping (Driver) -> Void) async -> () -> Void {
        let realtimeV2 = await MainActor.run { SupabaseManager.shared.client.realtimeV2 }
        do {
            let channel = realtimeV2.channel("public:driver_locations")
            let decoder = JSONDecoder()
            
            let streamTask = Task.detached {
                do {
                    for try await change in channel.postgresChange(AnyAction.self, table: "driver_locations") {
                        switch change {
                        case .insert(let insertion):
                            let row = try insertion.decodeRecord(as: DriverRow.self, decoder: decoder)
                            if realtimeUUIDStringsMatch(row.driver_id, driverId), let uuid = UUID(uuidString: row.driver_id) {
                                let d = Driver(id: uuid, coordinate: CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude), name: "Driver", color: .mint)
                                await MainActor.run { onUpdate(d) }
                            }
                        case .update(let update):
                            let row = try update.decodeRecord(as: DriverRow.self, decoder: decoder)
                            if realtimeUUIDStringsMatch(row.driver_id, driverId), let uuid = UUID(uuidString: row.driver_id) {
                                let d = Driver(id: uuid, coordinate: CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude), name: "Driver", color: .mint)
                                await MainActor.run { onUpdate(d) }
                            }
                        case .delete(let deletion):
                            let old = try deletion.decodeOldRecord(as: DriverRow.self, decoder: decoder)
                            if realtimeUUIDStringsMatch(old.driver_id, driverId), let uuid = UUID(uuidString: old.driver_id) {
                                let d = Driver(id: uuid, coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), name: "Driver", color: .mint)
                                await MainActor.run { onUpdate(d) }
                            }
                        }
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] single-driver stream ended:", error)
                }
            }
            
            try await channel.subscribeWithError()
            return {
                Task {
                    streamTask.cancel()
                    await channel.unsubscribe()
                }
            }
        } catch {
            SavariLog.debug("[RealtimeManager] single driver subscribe via SDK failed:", error)
        }
        
        // fallback polling unchanged...
        var pollingTask: Task<Void, Never>?
        let localInterval = pollingInterval
        pollingTask = Task.detached {
            while !Task.isCancelled {
                do {
                    let resp = try await SupabaseManager.shared.client.from("driver_locations").select().eq("driver_id", value: driverId).execute()
                    if let rows = Self.jsonArray(from: resp.data), let row = rows.first,
                       let lat = row["latitude"] as? Double, let lon = row["longitude"] as? Double {
                        let uuid = UUID(uuidString: driverId) ?? UUID()
                        let d = Driver(id: uuid, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), name: "Driver", color: .mint)
                        await MainActor.run { onUpdate(d) }
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] single-driver polling error:", error)
                }
                try? await Task.sleep(nanoseconds: UInt64(localInterval * 1_000_000_000))
            }
        }
        
        return {
            pollingTask?.cancel()
        }
    }
}
