import SwiftUI
import MapKit
import CoreLocation

struct MapPickerLocationSummary: View {
    let placemark: MKPlacemark

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(placemark.name ?? "Selected location")
                .font(.system(size: 18, weight: .semibold))

            if let title = placemark.title, title != placemark.name {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

struct MapPickerDistanceETA: View {
    let distanceMeters: CLLocationDistance?
    let etaSeconds: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let distanceMeters {
                Text(RideFormat.distance(distanceMeters))
                    .font(.system(size: 15, weight: .medium))
            } else {
                Text("Distance -")
                    .font(.system(size: 15, weight: .medium))
            }

            if let etaSeconds {
                Text("ETA \(RideFormat.eta(etaSeconds))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Text("ETA -")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MapPickerSelectionActions: View {
    let placemark: MKPlacemark
    let onCancel: () -> Void
    let onPick: (MKPlacemark) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Cancel", action: onCancel)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(20)

            Button {
                onPick(placemark)
            } label: {
                Text("Use Location")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .background(Capsule().fill(Color.white.opacity(0.9)))
            .foregroundColor(.black)
        }
    }
}

struct MapPickerPanelBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }
}
