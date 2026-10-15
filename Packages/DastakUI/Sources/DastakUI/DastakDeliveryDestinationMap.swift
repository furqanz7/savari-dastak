import SwiftUI
import MapKit
import MarketplaceFoundation
import MarketplaceInfrastructure
import MarketplaceDesignSystem

struct DastakDeliveryDestination {
    let title: String
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
    var revision: String { "\(title):\(latitude ?? .nan):\(longitude ?? .nan)" }
}

extension DastakDeliveryPartnerModel {
    var nextDestination: DastakDeliveryDestination? {
        if let mission = operations?.returnMission ?? v1Dispatch?.returnMission {
            if mission.status == "ASSIGNED" || mission.status == "AT_CUSTOMER" {
                let destination = mission.customerDestination
                return .init(title: "Return pickup", name: destination.recipient?.name ?? "Customer",
                    address: destination.address.display, latitude: destination.address.latitude, longitude: destination.address.longitude)
            }
            if mission.status == "RETURNING_TO_MERCHANTS",
               let stop = mission.stops.sorted(by: { $0.sequence < $1.sequence }).first(where: { $0.status != "COMPLETED" }) {
                return .init(title: "Return stop \(stop.sequence)", name: stop.branch.displayName,
                    address: stop.branch.address.display, latitude: stop.branch.location?.latitude ?? stop.branch.address.latitude,
                    longitude: stop.branch.location?.longitude ?? stop.branch.address.longitude)
            }
            return nil
        }
        if let mission = v1Dispatch?.currentMission {
            if mission.status == .deliveryRecovery { return nil }
            if [.allPackagesPickedUp, .outForDelivery, .arrived].contains(mission.status),
               let destination = mission.customerDestination {
                return .init(title: "Customer destination", name: destination.recipient?.name ?? "Customer",
                    address: destination.address.displayLine, latitude: destination.address.latitude, longitude: destination.address.longitude)
            }
            if let stop = mission.pickupStops.sorted(by: { $0.sequence < $1.sequence }).first(where: { $0.status != .completed }) {
                return .init(title: "Pickup \(stop.sequence) of \(mission.pickupCount)", name: stop.branch.displayName,
                    address: stop.branch.address.displayLine, latitude: stop.branch.address.latitude, longitude: stop.branch.address.longitude)
            }
        }
        if let job = courierDispatch?.currentJob {
            let delivering = [.pickedUp, .inTransit].contains(job.orderStatus)
            let point = delivering ? job.dropoff : job.store.pickup
            return .init(title: delivering ? "Customer destination" : "Merchant pickup", name: delivering ? "Customer" : job.store.name,
                address: delivering ? "Open directions for the assigned destination." : job.store.address, latitude: point.latitude, longitude: point.longitude)
        }
        if let job = parcelDispatch?.currentJob {
            let delivering = [.pickedUp, .inTransit].contains(job.parcel.status)
            let point = delivering ? job.parcel.dropoff : job.parcel.pickup
            return .init(title: delivering ? "Parcel destination" : "Parcel pickup", name: delivering ? job.parcel.recipient.name : "Parcel pickup",
                address: point.address, latitude: point.latitude, longitude: point.longitude)
        }
        return nil
    }
}

struct DastakDeliveryDestinationMap: View {
    let destination: DastakDeliveryDestination
    let current: Bool
    @State private var camera: MapCameraPosition = .automatic
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(destination.title, systemImage: "location.north.circle.fill").font(.headline)
            Text(destination.name).font(.title3.bold())
            Text(destination.address).font(.subheadline).foregroundStyle(.secondary)
            if !current { Label("Last-known destination · refresh before travelling", systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.orange) }
            if let coordinate = destination.coordinate {
                Map(position: $camera) { Marker(destination.name, coordinate: coordinate).tint(MarketplaceColors.dastakAccent.color) }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControls { MapCompass() }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomTrailing) {
                        MarketplaceFeedbackButton { withAnimation { camera = .automatic } } label: {
                            Image(systemName: "scope").padding(12).background(.regularMaterial, in: Circle())
                        }.accessibilityLabel("Recenter next-stop map").padding(10)
                    }
                if let url = URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d") {
                    Link(destination: url) { Label("Open directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
                        .disabled(!current)
                }
            } else { Text("Destination coordinates are unavailable. Refresh or contact Operations before travelling.").font(.footnote) }
        }.padding(16).marketplaceFlatSurface()
        .onChange(of: destination.revision) { _, _ in camera = .automatic }
    }
}
