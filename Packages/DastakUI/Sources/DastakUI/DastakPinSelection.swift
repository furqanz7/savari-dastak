import Foundation
import MarketplaceFoundation

/// Draft coordinates only. Saving an owned address and checking serviceability remain server operations.
@MainActor
final class DastakPinSelection: ObservableObject {
    @Published private(set) var location: DastakDeliveryLocation?
    @Published private(set) var isResolving = false
    @Published private(set) var notice: String?
    private var revision = UUID()

    init(location: DastakDeliveryLocation?) { self.location = location }

    func select(_ location: DastakDeliveryLocation) {
        revision = UUID()
        self.location = location
        isResolving = false
        notice = nil
    }

    func beginMove(latitude: Double, longitude: Double) -> UUID? {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        revision = UUID()
        // Never retain the previous street or saved-address identity for a different point.
        location = DastakDeliveryLocation(
            address: "Pinned location",
            point: GeoPoint(latitude: latitude, longitude: longitude)
        )
        isResolving = true
        notice = nil
        return revision
    }

    func finishMove(_ token: UUID, address: String?) {
        guard token == revision, let location else { return }
        let resolved = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = DastakDeliveryLocation(
            address: resolved?.isEmpty == false ? resolved! : "Pinned location",
            point: location.point
        )
        isResolving = false
        notice = resolved?.isEmpty == false ? nil : "The pin is set. Add your building and doorstep details even if the street name could not be found."
    }

    func invalidatePendingMove() {
        revision = UUID()
        isResolving = false
    }
}
