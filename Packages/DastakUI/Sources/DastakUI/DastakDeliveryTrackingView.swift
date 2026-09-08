import MapKit
import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakDeliveryTrackingView: View {
    let tracking: DastakDeliveryTracking
    var destination: CLLocationCoordinate2D? = nil
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let live = tracking.isLive(at: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34)).foregroundStyle(MarketplaceColors.dastakAccent.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tracking.riderName).font(.headline)
                        Text(phase).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(live ? "Live" : "Delayed", systemImage: live ? "location.fill" : "location.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(live ? MarketplaceColors.success.color : Color.secondary)
                }
                if tracking.location != nil || destination != nil {
                    Map(position: $camera) {
                        if let destination { Marker("Delivery destination", coordinate: destination) }
                        if let point = tracking.location {
                            Annotation(tracking.riderName, coordinate: CLLocationCoordinate2D(
                                latitude: point.latitude, longitude: point.longitude)) {
                                Image(systemName: riderSymbol)
                                    .font(.headline).foregroundStyle(.white).padding(11)
                                    .background(live ? MarketplaceColors.dastakAccent.color : Color.gray, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                            }
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControls { MapCompass() }
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomTrailing) {
                        Button { withAnimation { camera = .automatic } } label: {
                            Image(systemName: "scope").padding(10).background(.regularMaterial, in: Circle())
                        }
                        .accessibilityLabel("Recenter delivery map").padding(12)
                    }
                    .onChange(of: tracking.missionId) { _, _ in camera = .automatic }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: live ? "dot.radiowaves.left.and.right" : "clock")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(live ? "Location updates automatically" :
                            tracking.location == nil ? "Waiting for the rider’s first location" : "Last-known location · not live")
                        if !live {
                            Text("The rider may have weak GPS or no connection. We’ll update this map when a fresh location arrives.")
                        }
                        if let updated = DastakDeliveryTracking.date(tracking.recordedAt) {
                            Text("Updated \(updated, style: .relative) ago")
                        }
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        }
    }

    private var phase: String {
        switch tracking.phase {
        case "ASSIGNED": "Your delivery partner is assigned"
        case "EN_ROUTE_TO_PICKUPS", "PICKUP_IN_PROGRESS": "Collecting the order"
        case "ALL_PACKAGES_PICKED_UP": "Every package is collected"
        case "OUT_FOR_DELIVERY": "On the way to the customer"
        case "ARRIVED": "At the delivery destination"
        case "DELIVERY_RECOVERY": "Delivery needs assistance"
        default: "Delivery in progress"
        }
    }
    private var riderSymbol: String {
        switch tracking.transportType {
        case "WALKING": "figure.walk"
        case "BICYCLE": "bicycle"
        case "CAR", "GOODS_VEHICLE": "car.fill"
        default: "scooter"
        }
    }
}

struct DastakArrivalButton: View {
    let eligibility: DastakArrivalEligibility?
    let busy: Bool
    let action: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Button("I’ve arrived", action: action)
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .disabled(busy || eligibility?.canArrive(at: context.date) != true)
                if eligibility?.canArrive(at: context.date) != true {
                    Label(message, systemImage: "location.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private var message: String {
        if eligibility?.reason == "TOO_FAR", let distance = eligibility?.distanceMeters {
            return "\(Int(distance.rounded())) m away · Arrival unlocks within 50 m."
        }
        if eligibility?.reason == "DESTINATION_UNAVAILABLE" {
            return "Destination is not available for arrival yet."
        }
        return "Waiting for a fresh, precise GPS location within 50 m."
    }
}
