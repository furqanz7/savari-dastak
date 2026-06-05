import SwiftUI
import Foundation
import CoreLocation
import Supabase

extension DashboardViewModelRealtime {
    func fetchInitialDrivers() async {
        do {
            let response = try await SupabaseManager.shared.client
                .from("driver_locations")
                .select()
                .execute()
            if let rows = jsonArray(from: response.data) {
                let drivers = parseDriverRows(rows)
                await MainActor.run { self.drivers = drivers }
            }
        } catch {
            SavariLog.debug("fetchInitialDrivers error:", error)
        }
    }

    func subscribeToDriverLocations() async {
        realtimeCancel?()
        isRealtimeActive = true
        realtimeCancel = await RealtimeManager.shared.subscribeDriverLocations { [weak self] incoming in
            Task { @MainActor in
                self?.applyDriverLocationUpdates(incoming)
            }
        }
    }

    @MainActor
    private func applyDriverLocationUpdates(_ incoming: [Driver]) {
        for driver in incoming {
            if let index = drivers.firstIndex(where: { $0.id == driver.id }) {
                if driver.coordinate.latitude == 0 && driver.coordinate.longitude == 0 {
                    drivers.remove(at: index)
                } else {
                    let old = drivers[index]
                    drivers[index] = Driver(
                        id: old.id,
                        coordinate: driver.coordinate,
                        name: old.name,
                        color: old.color
                    )
                }
            } else {
                drivers.append(driver)
            }
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
                name: driverMapLabel(for: uuid),
                color: .blue
            )
        }
    }

    private func driverMapLabel(for uuid: UUID) -> String {
        if uuidStringsMatch(uuid.uuidString, SavariSessionStore.authToken) {
            return "You"
        }
        return "Driver"
    }
}
