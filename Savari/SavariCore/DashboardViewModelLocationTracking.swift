import SwiftUI
import Combine
import CoreLocation

extension DashboardViewModelRealtime {
    func startGPSUpdates(for role: String) {
        GPSLocationPusher.shared.start()

        guard role.lowercased().contains("driver") else {
            return
        }

        gpsCancellable = GPSLocationPusher.shared.$current
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coordinate in
                self?.updateCurrentDriverMarker(coordinate)
            }
    }

    private func updateCurrentDriverMarker(_ coordinate: CLLocationCoordinate2D) {
        if let auth = SavariSessionStore.authToken, let uuid = UUID(uuidString: auth) {
            if let index = drivers.firstIndex(where: { $0.id == uuid }) {
                drivers[index].coordinate = coordinate
            } else {
                let driver = Driver(id: uuid, coordinate: coordinate, name: "You", color: .mint)
                drivers.insert(driver, at: 0)
            }
            return
        }

        if !drivers.isEmpty {
            drivers[0].coordinate = coordinate
        }
    }
}
