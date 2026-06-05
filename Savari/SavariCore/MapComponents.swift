import SwiftUI
@preconcurrency import Foundation
import MapKit
import CoreLocation


// MARK: - DriverAnnotationView
struct DriverAnnotationView: View {
    var driver: Driver
    var body: some View {
        VStack(spacing: 6) {
            ZStack { Circle().fill(driver.color).frame(width: 44, height: 44).shadow(radius: 3)
                Image(systemName: "car.fill").font(.system(size: 18)).foregroundColor(.white)
            }
            Text(driver.name).font(.caption2).padding(6).background(.ultraThinMaterial).cornerRadius(6)
        }
        .fixedSize()
    }
}

struct BoardingCodeView: View {
    let code: String
    let ttlSeconds: Int?
    var body: some View {
        VStack(spacing: 12) {
            Text("Boarding Code").font(.headline)
            Text(code).font(.system(size: 36, weight: .bold)).padding(8).background(.ultraThinMaterial).cornerRadius(12)
            if let ttl = ttlSeconds {
                Text("Expires in \(ttl) sec").font(.caption).foregroundColor(.secondary)
            }
        }.padding()
    }
}

// MARK: - FloatingRideCard
struct FloatingRideCard: View {
    let title: String
    let subtitle: String
    let acceptTitle: String
    let acceptAction: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundColor(.secondary)
            
            Button(action: acceptAction) {
                Text(acceptTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

// MARK: - BottomSheet
struct BottomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let maxHeight: CGFloat
    let content: Content

    @GestureState private var translation: CGFloat = 0

    init(
        isPresented: Binding<Bool>,
        maxHeight: CGFloat = 420,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            if isPresented {
                // Dimmed background
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { isPresented = false }
                    }

                VStack {
                    Spacer()

                    VStack(spacing: 0) {
                        // Drag handle (still belongs to sheet mechanics)
                        Capsule()
                            .fill(Color.secondary.opacity(0.6))
                            .frame(width: 44, height: 6)
                            .padding(.top, 8)
                            .padding(.bottom, 8)

                        // 🚨 NO BACKGROUND HERE
                        content
                            .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: maxHeight)
                    .offset(y: max(0, translation))
                    .gesture(
                        DragGesture()
                            .updating($translation) { value, state, _ in
                                state = value.translation.height
                            }
                            .onEnded { value in
                                if value.translation.height > 120 {
                                    withAnimation { isPresented = false }
                                }
                            }
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: isPresented)
    }
}

// MARK: - PrimaryButtonStyle
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(colorScheme == .dark ? Color.blue.opacity(configuration.isPressed ? 0.6 : 0.9) : Color.blue))
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

