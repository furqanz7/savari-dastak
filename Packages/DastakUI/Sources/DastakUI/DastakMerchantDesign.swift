import SwiftUI
import MarketplaceDesignSystem
#if os(iOS)
import UIKit
#endif

/// Merchant-only presentation. No timers, business state or mutation authority.
struct DastakMerchantHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(eyebrow).tracking(1.8)
            }.font(.caption.weight(.bold)).foregroundStyle(MarketplaceColors.accent(for: scheme))
            Text(title).font(MarketplaceTypography.instrumentSerif(size: 38)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(LinearGradient(colors: [MarketplaceColors.accent(for: scheme).opacity(0.65), .clear],
                startPoint: .leading, endPoint: .trailing)).frame(height: 1).padding(.top, 6)
                .accessibilityHidden(true)
        }.padding(.top, 12)
    }
}

/// Vertical at accessibility sizes; also falls back for narrow local widths.
struct DastakMerchantAdaptiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 12, content: content) }
        else { ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12, content: content)
            VStack(alignment: .leading, spacing: 12, content: content)
        } }
    }
}

struct DastakMerchantValueRow: View {
    let title: String
    let value: String
    var body: some View {
        DastakMerchantAdaptiveRow {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).frame(maxWidth: .infinity, alignment: .trailing)
        }.accessibilityElement(children: .combine)
    }
}

struct DastakMerchantDeskOverview: View {
    let incoming: Int
    let preparing: Int
    let ready: Int
    @Binding var selection: DastakMerchantQueue
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 10) {
            metric(incoming, "New requests", "bell.badge", .incoming)
            metric(preparing, "Preparing", "timer", .preparing)
            metric(ready, "Ready", "shippingbox", .ready)
        }
    }
    private func metric(_ count: Int, _ title: String, _ symbol: String, _ queue: DastakMerchantQueue) -> some View {
        MarketplaceFeedbackButton(haptic: .selection) { selection = queue } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.subheadline).foregroundStyle(MarketplaceColors.accent(for: scheme)).accessibilityHidden(true)
                Text(count.formatted()).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).marketplaceFlatSurface()
                .overlay(RoundedRectangle(cornerRadius: MarketplaceMetrics.compactCornerRadius)
                    .strokeBorder(selection == queue ? MarketplaceColors.accent(for: scheme) : .clear, lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: MarketplaceMetrics.compactCornerRadius))
        }.buttonStyle(.plain).accessibilityLabel("\(count) \(title)").accessibilityAddTraits(selection == queue ? .isSelected : [])
    }
}

struct DastakMerchantQueuePicker: View {
    @Binding var selection: DastakMerchantQueue
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if typeSize.isAccessibilitySize {
            Picker("Order queue", selection: $selection) {
                ForEach(DastakMerchantQueue.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("merchant.orders.queue")
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DastakMerchantQueue.allCases, id: \.self) { queue in
                            MarketplaceFeedbackButton(haptic: .selection) { selection = queue } label: {
                                Text(queue.rawValue).font(.subheadline.weight(.semibold)).fixedSize()
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .foregroundStyle(selection == queue ? MarketplaceColors.primaryActionForeground.color : MarketplaceColors.primaryText(for: scheme))
                                    .background(selection == queue ? MarketplaceColors.primaryAction.color : MarketplaceColors.surface(for: scheme), in: Capsule())
                            }.buttonStyle(.plain).id(queue).accessibilityAddTraits(selection == queue ? .isSelected : [])
                        }
                    }.padding(.vertical, 2)
                }.onChange(of: selection) { _, next in proxy.scrollTo(next, anchor: .center) }
            }.accessibilityIdentifier("merchant.orders.queue")
        }
    }
}

struct DastakMerchantDetailLink: View {
    let action: () -> Void
    var body: some View {
        MarketplaceFeedbackButton(action: action) {
            HStack(spacing: 12) {
                Label("View full order", systemImage: "doc.text.magnifyingglass").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }.frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Local styling only. Dynamic labels can wrap without shrinking their hit area.
struct DastakMerchantActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(primary ? MarketplaceColors.primaryActionForeground.color : MarketplaceColors.primaryText(for: scheme))
            .background(primary ? MarketplaceColors.primaryAction.color : MarketplaceColors.surface(for: scheme), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(primary ? .clear : MarketplaceColors.divider(for: scheme), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.42)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DastakMerchantKeyboardDismiss: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Dismiss keyboard")
            } }
        #else
        content
        #endif
    }
}
