import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MapPickerView: View {
    @Binding var selectedItem: MKMapItem?
    var onPick: (MKMapItem) -> Void

    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var pickedPlacemark: MKPlacemark?
    @State private var distanceMeters: CLLocationDistance?
    @State private var etaSeconds: TimeInterval?
    @State private var showHint = true
    @State private var showTopCloseHint = true
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack(alignment: .top) {
            MapPickerRepresentable(
                pickedCoordinate: $pickedCoordinate,
                pickedPlacemark: $pickedPlacemark,
                onSelectPlacemark: handlePlacemarkSelection,
                onRouteComputed: handleRouteComputed
            )
            .edgesIgnoringSafeArea(.all)

            closeTapArea
            closeHint
            longPressHint
            pickedLocationPanel
        }
        .interactiveDismissDisabled(false)
    }

    private var closeTapArea: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 120)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.22)) {
                        showTopCloseHint = false
                    }
                    dismiss()
                }

            Spacer()
        }
        .allowsHitTesting(showTopCloseHint)
    }

    @ViewBuilder
    private var closeHint: some View {
        if showTopCloseHint {
            VStack {
                Text("Tap here/Drag down to close")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 6)
                    .padding(.top, 18)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) {
                            showTopCloseHint = false
                        }
                        dismiss()
                    }

                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var longPressHint: some View {
        if showHint {
            VStack {
                Spacer()
                Text("Long-press to pick a location")
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 6)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showHint = false
                        }
                    }
                    .padding(.bottom, 28)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var pickedLocationPanel: some View {
        if let placemark = pickedPlacemark {
            VStack(spacing: 14) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                locationSummary(for: placemark)

                HStack(spacing: 16) {
                    distanceETA
                    Spacer()
                    selectionActions(for: placemark)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(panelBackground)
            .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func locationSummary(for placemark: MKPlacemark) -> some View {
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

    private var distanceETA: some View {
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

    private func selectionActions(for placemark: MKPlacemark) -> some View {
        HStack(spacing: 10) {
            Button("Cancel") {
                clearSelection()
                withAnimation(.easeInOut) {
                    showHint = true
                    showTopCloseHint = true
                }
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(20)

            Button {
                onPick(MKMapItem(placemark: placemark))
                presentationMode.wrappedValue.dismiss()
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

    private var panelBackground: some View {
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

    private func handlePlacemarkSelection(_ placemark: MKPlacemark) {
        pickedPlacemark = placemark
        selectedItem = MKMapItem(placemark: placemark)

        withAnimation(.easeOut(duration: 0.22)) {
            showHint = false
            showTopCloseHint = false
        }
    }

    private func handleRouteComputed(distance: CLLocationDistance?, eta: TimeInterval?) {
        distanceMeters = distance
        etaSeconds = eta
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private func clearSelection() {
        pickedCoordinate = nil
        pickedPlacemark = nil
        distanceMeters = nil
        etaSeconds = nil
        selectedItem = nil
    }
}
