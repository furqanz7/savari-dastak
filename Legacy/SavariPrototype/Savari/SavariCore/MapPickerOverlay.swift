import SwiftUI
import MapKit
import CoreLocation

struct MapPickerOverlay: View {
    let pickedPlacemark: MKPlacemark?
    let distanceMeters: CLLocationDistance?
    let etaSeconds: TimeInterval?
    @Binding var showHint: Bool
    @Binding var showTopCloseHint: Bool
    let onDismiss: () -> Void
    let onCancelSelection: () -> Void
    let onPick: (MKPlacemark) -> Void

    var body: some View {
        closeTapArea
        closeHint
        longPressHint
        pickedLocationPanel
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
                    onDismiss()
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
                        onDismiss()
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

                MapPickerLocationSummary(placemark: placemark)

                HStack(spacing: 16) {
                    MapPickerDistanceETA(distanceMeters: distanceMeters, etaSeconds: etaSeconds)
                    Spacer()
                    MapPickerSelectionActions(
                        placemark: placemark,
                        onCancel: onCancelSelection,
                        onPick: onPick
                    )
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(MapPickerPanelBackground())
            .shadow(color: Color.black.opacity(0.28), radius: 20, y: 10)
            .padding(.horizontal, 14)
            .padding(.bottom, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
