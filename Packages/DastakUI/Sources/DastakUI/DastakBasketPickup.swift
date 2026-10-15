import MarketplaceDesignSystem
import SwiftUI

struct DastakOpenCartAction: @unchecked Sendable {
    let action: @MainActor (DastakBasketService) -> Void
    @MainActor func callAsFunction(_ service: DastakBasketService) { action(service) }
}

private struct DastakOpenCartKey: EnvironmentKey {
    static let defaultValue = DastakOpenCartAction(action: { _ in })
}

extension EnvironmentValues {
    var dastakOpenCart: DastakOpenCartAction {
        get { self[DastakOpenCartKey.self] }
        set { self[DastakOpenCartKey.self] = newValue }
    }
}

struct DastakBasketPrompt: Equatable, Sendable {
    let id = UUID()
    let service: DastakBasketService
    let expiresAt: Date
}

struct DastakBasketFlight: Identifiable, Equatable, Sendable {
    let id = UUID()
    let service: DastakBasketService
    let productID: UUID?
    let imageKey: String?
}

extension DastakBasketService {
    var pickupSymbol: String { self == .grocery ? "basket" : "fork.knife" }
    var pickupAnchor: String { "pickup-\(rawValue)" }
    var dockAnchor: String { "dock-\(rawValue)" }
    func itemAnchor(_ id: UUID) -> String { "\(rawValue)-\(id)" }
}

private struct BasketAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func dastakBasketAnchor(_ key: String) -> some View {
        anchorPreference(key: BasketAnchors.self, value: .bounds) { [key: $0] }
    }

    func dastakBasketExperience(model: DastakCustomerModel, service: DastakBasketService,
                                showsDock: Bool = true, openCart: @escaping () -> Void) -> some View {
        modifier(DastakBasketExperience(model: model, service: service, showsDock: showsDock, openCart: openCart))
    }
}

struct DastakBasketPickupButton: View {
    @ObservedObject var model: DastakCustomerModel
    let service: DastakBasketService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        MarketplaceFeedbackButton { model.pickUpBasket(service) } label: {
            Image(systemName: service.pickupSymbol)
                .font(.title3)
                .symbolEffect(.bounce, options: .repeat(2), value: reduceMotion ? nil : model.basketPrompt?.id)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dastakBasketAnchor(service.pickupAnchor)
        // Keep the anchor and toolbar spacing while the icon flies to the dock.
        .opacity(model.hasBasket(service) ? 0 : 1)
        .allowsHitTesting(!model.hasBasket(service))
        .accessibilityHidden(model.hasBasket(service))
        .accessibilityLabel("Pick up \(service.title) basket")
        .accessibilityIdentifier("dastak.pickup.\(service.rawValue)")
    }
}

struct DastakBasketDock: View {
    @ObservedObject var model: DastakCustomerModel
    let service: DastakBasketService
    let openCart: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if model.showsBasketDock(service) {
            let basket = model.baskets[service]
            let summary = "\(basket.itemCount) \(basket.itemCount == 1 ? "item" : "items") · \(DastakFormatting.money(basket.subtotal)) estimated"
            MarketplaceFeedbackButton {
                guard !model.baskets[service].isEmpty else { return }
                openCart()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: service.pickupSymbol)
                        .font(.title3)
                        .frame(width: 32, height: 36)
                        .dastakBasketAnchor(service.dockAnchor)
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : basket.itemCount)
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(summary).font(.caption.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 6)
                            Label("Take to Cart", systemImage: "arrow.right").font(.caption.bold())
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(summary).font(.caption.weight(.semibold))
                            Label("Take to Cart", systemImage: "arrow.right").font(.caption.bold())
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(basket.isEmpty)
            .marketplaceGlass(cornerRadius: 18)
            .accessibilityLabel("\(service.title) basket, \(summary), Take to Cart")
            .accessibilityIdentifier("dastak.bucket")
        }
    }
}

private struct DastakBasketExperience: ViewModifier {
    @ObservedObject var model: DastakCustomerModel
    let service: DastakBasketService
    let showsDock: Bool
    let openCart: () -> Void
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if showsDock, model.showsBasketDock(service) {
                    DastakBasketDock(model: model, service: service, openCart: openCart).padding(.horizontal, 12)
                }
            }
            .overlay(alignment: .bottom) {
                if let prompt = model.basketPrompt {
                    HStack(spacing: 10) {
                        Text("Pick up the basket first before adding an item.")
                            .font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        // Also reachable inside search, saved items and other presented screens.
                        DastakBasketPickupButton(model: model, service: prompt.service)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 12)
                    .padding(.bottom, showsDock && model.showsBasketDock(service) ? 80 : 12)
                    .accessibilityIdentifier("dastak.basket-pickup-prompt")
                }
            }
            .overlayPreferenceValue(BasketAnchors.self) { anchors in
                GeometryReader { geometry in
                    BasketFlightOverlay(model: model, service: service, anchors: anchors, geometry: geometry)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

private struct BasketFlightOverlay: View {
    struct Flight: Identifiable {
        let event: DastakBasketFlight
        let from: CGPoint
        let to: CGPoint
        var id: UUID { event.id }
    }
    @ObservedObject var model: DastakCustomerModel
    let service: DastakBasketService
    let anchors: [String: Anchor<CGRect>]
    let geometry: GeometryProxy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flights: [Flight] = []

    var body: some View {
        ZStack {
            ForEach(flights) { flight in
                FlyingBasketItem(flight: flight, reduceMotion: reduceMotion) {
                    flights.removeAll { $0.id == flight.id }
                }
            }
        }
        .onChange(of: model.basketFlight) { _, event in
            guard let event, event.service == service else { return }
            let sourceKey = event.productID.map(service.itemAnchor) ?? service.pickupAnchor
            let source = anchors[sourceKey].map { geometry[$0] }
            let destination = anchors[service.dockAnchor].map { geometry[$0] }
            // Clamp an offscreen card to the visible panel. Never fly from another service.
            let fallback = event.productID == nil
                ? CGPoint(x: geometry.size.width - 40, y: 32)
                : CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let start = CGPoint(x: min(geometry.size.width - 28, max(28, source?.midX ?? fallback.x)),
                                y: min(geometry.size.height - 90, max(28, source?.midY ?? fallback.y)))
            let end = CGPoint(x: destination?.midX ?? 40, y: destination?.midY ?? geometry.size.height - 38)
            flights.append(.init(event: event, from: start, to: end))
        }
    }
}

private struct FlyingBasketItem: View {
    let flight: BasketFlightOverlay.Flight
    let reduceMotion: Bool
    let finished: () -> Void
    @State private var progress: CGFloat = 0
    @State private var pop: CGFloat = 0.65
    var body: some View {
        Group {
            if flight.event.productID != nil {
                DastakProductArtwork(imageKey: flight.event.imageKey, fallbackSymbol: flight.event.service.pickupSymbol)
            } else {
                Image(systemName: flight.event.service.pickupSymbol).font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
        }
        .frame(width: 48, height: 48)
        .scaleEffect(pop)
        .modifier(BasketFlightPath(progress: progress, from: flight.from, to: flight.to, reduced: reduceMotion))
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.18)) { pop = 1.3 }
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: reduceMotion ? 0.18 : 0.6)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 650))
            finished()
        }
    }
}

private struct BasketFlightPath: AnimatableModifier {
    nonisolated var progress: CGFloat
    let from: CGPoint
    let to: CGPoint
    let reduced: Bool
    nonisolated var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content
            .scaleEffect(reduced ? 1 : 1 - progress * 0.7)
            .opacity(Double(1 - max(0, progress - 0.8) * 5))
            .position(x: reduced ? to.x : from.x + (to.x - from.x) * progress,
                      y: reduced ? to.y : from.y + (to.y - from.y) * progress - sin(progress * .pi) * 80)
    }
}
