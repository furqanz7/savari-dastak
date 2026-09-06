import SwiftUI

/// A full-screen product browser, not a card nested inside a system bottom sheet.
/// Each page owns its scroll position and role-specific controls. The whole page,
/// including its pinned purchase/stock bar, moves with the horizontal scroll view.
struct DastakProductDetailCarousel<Page: View>: View {
    let products: [DastakDetailProduct]
    @Binding var selectedID: UUID
    var navigationDisabled = false
    @ViewBuilder let page: (UUID, @escaping (UUID) -> Void) -> Page
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageID: UUID?
    @State private var progress: Double
    @State private var pickerDrag: CGFloat = 0

    init(products: [DastakDetailProduct], selectedID: Binding<UUID>, navigationDisabled: Bool = false,
         @ViewBuilder page: @escaping (UUID, @escaping (UUID) -> Void) -> Page) {
        self.products = products
        _selectedID = selectedID
        self.navigationDisabled = navigationDisabled
        self.page = page
        _pageID = State(initialValue: selectedID.wrappedValue)
        _progress = State(initialValue: Double(products.firstIndex { $0.id == selectedID.wrappedValue } ?? 0))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, 580)
            let pickerHeight: CGFloat = geometry.size.height < 650 ? 88 : 104
            VStack(spacing: 14) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                            page(product.id, select)
                                .padding(.horizontal, 16)
                                .frame(width: width)
                                .background(GeometryReader { frame in
                                    Color.clear.preference(key: ProductPagePositionKey.self,
                                        value: [index: frame.frame(in: .named("product-deck")).minX])
                                })
                                .id(product.id)
                                .accessibilityHidden(product.id != selectedID)
                        }
                    }.scrollTargetLayout()
                }
                .coordinateSpace(name: "product-deck")
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageID)
                .scrollIndicators(.hidden)
                .scrollDisabled(navigationDisabled)
                .onPreferenceChange(ProductPagePositionKey.self) { positions in
                    if let position = positions.min(by: { abs($0.value) < abs($1.value) }) {
                        progress = min(Double(max(0, products.count - 1)), max(0, Double(position.key) - position.value / width))
                    }
                }
                .onChange(of: pageID) { _, id in
                    if let id, !navigationDisabled { selectedID = id }
                }
                .onChange(of: selectedID) { _, id in
                    if pageID != id { select(id) }
                }
                .accessibilityIdentifier("product-card-pager")
                .accessibilityAction(named: "Next product") { move(1) }
                .accessibilityAction(named: "Previous product") { move(-1) }

                picker(width: width, height: pickerHeight)
            }
            .padding(.top, 12)
            .frame(width: width, height: geometry.size.height)
            .frame(maxWidth: .infinity)
        }
        // No rounded outer surface, detents or picker panel. Only the individual
        // cards are opaque; the catalogue remains visible through this scrim.
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color(red: 0.16, green: 0.18, blue: 0.19).opacity(0.40))
                .ignoresSafeArea()
        }
        .interactiveDismissDisabled(navigationDisabled)
    }

    private func select(_ id: UUID) {
        guard !navigationDisabled, products.contains(where: { $0.id == id }) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { pageID = id }
        selectedID = id
    }

    private func move(_ step: Int) {
        guard let index = products.firstIndex(where: { $0.id == selectedID }),
              let next = DastakProductDetailInteraction.nextIndex(current: index, count: products.count, step: step) else { return }
        select(products[next].id)
    }

    private func picker(width: CGFloat, height: CGFloat) -> some View {
        let position = min(Double(max(0, products.count - 1)), max(0, progress - Double(pickerDrag / 86)))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(products.enumerated()).filter { abs(Double($0.offset) - position) < 3.4 }, id: \.element.id) { index, product in
                let distance = Double(index) - position
                let pose = DastakProductDetailInteraction.pickerPose(distance: distance)
                Button { select(product.id) } label: {
                    DastakProductArtwork(imageKey: product.imageKey, detail: true)
                        .padding(7)
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.93), in: Circle())
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(.white, lineWidth: 2).padding(-4)
                                .opacity(max(0, 1 - abs(distance) * 2))
                        }
                }
                .buttonStyle(.plain)
                .scaleEffect(pose.scale)
                .rotationEffect(.degrees(reduceMotion ? 0 : pose.rotation))
                .opacity(pose.opacity)
                .position(x: width / 2 + distance * 86, y: 38 + pose.drop)
                .disabled(navigationDisabled)
                .accessibilityLabel("View \(product.name), \(product.packSize)")
                .accessibilityAddTraits(product.id == selectedID ? .isSelected : [])
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !navigationDisabled, abs(value.translation.width) > abs(value.translation.height) else { return }
                pickerDrag = value.translation.width
            }
            .onEnded { value in
                guard !navigationDisabled,
                      abs(value.translation.width) > abs(value.translation.height) else { pickerDrag = 0; return }
                let destination = min(products.count - 1, max(0, Int((progress - Double(value.predictedEndTranslation.width / 86)).rounded())))
                pickerDrag = 0
                if products.indices.contains(destination) { select(products[destination].id) }
            })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Product picker")
        .accessibilityValue("Product \(Int(progress.rounded()) + 1) of \(products.count)")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { move(1) } else if direction == .decrement { move(-1) }
        }
        .accessibilityIdentifier("product-orbit-picker")
    }
}

private struct ProductPagePositionKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    @ViewBuilder
    func dastakProductOverlay<Item: Identifiable, Content: View>(item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content) -> some View {
#if os(iOS)
        fullScreenCover(item: item) { value in
            content(value).presentationBackground(.clear)
        }
#else
        // Desktop gets a window-filling overlay too, never a nested sheet.
        overlay {
            if let value = item.wrappedValue { content(value) }
        }
#endif
    }
}
