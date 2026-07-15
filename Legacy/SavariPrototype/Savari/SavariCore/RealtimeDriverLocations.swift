import SwiftUI
import Foundation
import CoreLocation
import MapKit
import Supabase
import PostgREST
import Realtime

extension RealtimeManager {
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
                            let row = try insertion.decodeRecord(as: DriverRow.self, decoder: decoder)
                            if let driver = Self.driver(from: row, color: .blue) {
                                await MainActor.run { onUpdate([driver]) }
                            }
                        case .update(let update):
                            let row = try update.decodeRecord(as: DriverRow.self, decoder: decoder)
                            if let driver = Self.driver(from: row, color: .blue) {
                                await MainActor.run { onUpdate([driver]) }
                            }
                        case .delete(let deletion):
                            let old = try deletion.decodeOldRecord(as: DriverRow.self, decoder: decoder)
                            if let uuid = UUID(uuidString: old.driver_id) {
                                let driver = Driver(
                                    id: uuid,
                                    coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                    name: "Driver",
                                    color: .blue
                                )
                                await MainActor.run { onUpdate([driver]) }
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

        pollingTask?.cancel()
        pollingTask = Task.detached { [weak self] in
            guard let self else { return }
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
                            if realtimeUUIDStringsMatch(row.driver_id, driverId),
                               let driver = Self.driver(from: row, color: .mint) {
                                await MainActor.run { onUpdate(driver) }
                            }
                        case .update(let update):
                            let row = try update.decodeRecord(as: DriverRow.self, decoder: decoder)
                            if realtimeUUIDStringsMatch(row.driver_id, driverId),
                               let driver = Self.driver(from: row, color: .mint) {
                                await MainActor.run { onUpdate(driver) }
                            }
                        case .delete(let deletion):
                            let old = try deletion.decodeOldRecord(as: DriverRow.self, decoder: decoder)
                            if realtimeUUIDStringsMatch(old.driver_id, driverId),
                               let uuid = UUID(uuidString: old.driver_id) {
                                let driver = Driver(
                                    id: uuid,
                                    coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                    name: "Driver",
                                    color: .mint
                                )
                                await MainActor.run { onUpdate(driver) }
                            }
                        }
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] single-driver stream ended:", error)
                }
            }

            try await channel.subscribeWithError()
            if let currentDriver = await Self.fetchDriverLocation(driverId: driverId, color: .mint) {
                await MainActor.run { onUpdate(currentDriver) }
            }
            return {
                Task {
                    streamTask.cancel()
                    await channel.unsubscribe()
                }
            }
        } catch {
            SavariLog.debug("[RealtimeManager] single driver subscribe via SDK failed:", error)
        }

        var pollingTask: Task<Void, Never>?
        let localInterval = pollingInterval
        pollingTask = Task.detached {
            while !Task.isCancelled {
                do {
                    let resp = try await SupabaseManager.shared.client
                        .from("driver_locations")
                        .select()
                        .eq("driver_id", value: driverId)
                        .execute()
                    if let rows = Self.jsonArray(from: resp.data),
                       let row = rows.first,
                       let lat = row["latitude"] as? Double,
                       let lon = row["longitude"] as? Double {
                        let uuid = UUID(uuidString: driverId) ?? UUID()
                        let driver = Driver(
                            id: uuid,
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            name: "Driver",
                            color: .mint
                        )
                        await MainActor.run { onUpdate(driver) }
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

    nonisolated private static func fetchDriverLocation(driverId: String, color: Color) async -> Driver? {
        do {
            let response = try await SupabaseManager.shared.client
                .from("driver_locations")
                .select()
                .eq("driver_id", value: driverId)
                .single()
                .execute()

            guard let row = jsonObject(from: response.data),
                  let latitude = row["latitude"] as? Double,
                  let longitude = row["longitude"] as? Double,
                  let uuid = UUID(uuidString: driverId) else {
                return nil
            }

            return Driver(
                id: uuid,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                name: "Driver",
                color: color
            )
        } catch {
            SavariLog.debug("[RealtimeManager] initial driver location fetch failed:", error)
            return nil
        }
    }

    private func fetchDriverLocationsOnce(onUpdate: @escaping ([Driver]) -> Void) async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("driver_locations")
                .select()
                .execute()

            if let rows = Self.jsonArray(from: response.data) {
                await MainActor.run { onUpdate(parseDriverRows(rows)) }
                return
            }

            if let dict = Self.jsonObject(from: response.data),
               let inner = dict["data"] as? [[String: Any]] {
                await MainActor.run { onUpdate(parseDriverRows(inner)) }
            }
        } catch {
            SavariLog.debug("[RealtimeManager] polling fetch error:", error.localizedDescription)
        }
    }

    private func parseDriverRows(_ rows: [[String: Any]]) -> [Driver] {
        rows.compactMap { row in
            guard let idString = row["driver_id"] as? String,
                  let latitude = row["latitude"] as? Double,
                  let longitude = row["longitude"] as? Double else {
                return nil
            }
            let uuid = UUID(uuidString: idString) ?? UUID()
            return Driver(
                id: uuid,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                name: "Driver",
                color: .blue
            )
        }
    }

    nonisolated private static func driver(from row: DriverRow, color: Color) -> Driver? {
        guard let uuid = UUID(uuidString: row.driver_id) else {
            return nil
        }

        return Driver(
            id: uuid,
            coordinate: CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude),
            name: "Driver",
            color: color
        )
    }
}
