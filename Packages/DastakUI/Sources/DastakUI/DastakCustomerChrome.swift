import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI

struct DastakCustomerChrome: View {
    let navigation: DastakCustomerNavigation
    let locationLabel: String
    let map: DastakV1CatalogueBrowseMap?
    let selectSection: (DastakCustomerSection) -> Void
    let selectService: (DastakCustomerService) -> Void
    let chooseLocation: () -> Void
    let openDirectory: (String) -> Void
    let availableWidth: CGFloat
    var compact = false
    @State private var controlSheet: DastakCustomerControlSheet?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if compact { compactChrome }
            else { inlineChrome }
        }
        .sheet(item: $controlSheet) { sheet in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if sheet == .navigation {
                            ForEach(DastakCustomerSection.allCases, id: \.self) { section in
                                MarketplaceFeedbackButton {
                                    controlSheet = nil
                                    selectSection(section)
                                } label: {
                                    Label(section.rawValue, systemImage: section.symbol)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .padding(10)
                                        .background(navigation.section == section ? MarketplaceColors.dastakAccent.color.opacity(0.16) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                                .accessibilityIdentifier("dastak.navigation.\(section.rawValue.lowercased())")
                            }
                        } else {
                            ForEach(DastakCustomerService.allCases, id: \.self) { service in
                                MarketplaceFeedbackButton {
                                    controlSheet = nil
                                    selectService(service)
                                } label: {
                                    Label(service.isAvailable ? service.rawValue : "\(service.rawValue) · Coming soon", systemImage: service.symbol)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .padding(10)
                                        .background(navigation.service == service ? MarketplaceColors.dastakAccent.color.opacity(0.16) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .disabled(!service.isAvailable)
                                .accessibilityAddTraits(navigation.service == service ? .isSelected : [])
                                .accessibilityIdentifier("dastak.service.\(service.rawValue.lowercased())")
                            }
                            if navigation.service == .grocery { directoryContents(expanded: true) }
                        }
                    }
                    .padding(16)
                }
                .navigationTitle(sheet.title)
                .dastakInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        MarketplaceFeedbackButton("Close") { controlSheet = nil }
                            .accessibilityIdentifier("dastak.controls.close")
                    }
                }
                .marketplacePage()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var compactChrome: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                DastakWordmark(size: 24).foregroundStyle(.white)
                    .shadow(color:.black.opacity(0.5),radius:3,y:1)
                    .accessibilityIdentifier("dastak.wordmark")
                MarketplaceFeedbackButton(action: chooseLocation) {
                    Group {
                        if dynamicTypeSize >= .xxxLarge { Text(locationLabel) }
                        else { Label(locationLabel, systemImage: "mappin.and.ellipse") }
                    }
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .accessibilityLabel("Delivery location, \(locationLabel)")
                .accessibilityIdentifier("dastak.location")
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { compactNavigation; Spacer(minLength: 0); compactServices }
                VStack(spacing: 4) {
                    HStack { compactNavigation; Spacer(minLength: 0) }
                    HStack { Spacer(minLength: 0); compactServices }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var compactNavigation: some View {
        MarketplaceFeedbackButton { controlSheet = .navigation } label: {
            Label(navigation.section.rawValue, systemImage: "sidebar.left")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .modifier(DastakChromeLiquidGlass())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Navigation, \(navigation.section.rawValue)")
        .accessibilityHint("Opens Home, Orders, Profile and Settings")
        .accessibilityIdentifier("dastak.controls.navigation")
    }

    private var compactServices: some View {
        MarketplaceFeedbackButton { controlSheet = .services } label: {
            Label(navigation.service.rawValue, systemImage: "sidebar.right")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .modifier(DastakChromeLiquidGlass())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Services and aisles, \(navigation.service.rawValue)")
        .accessibilityIdentifier("dastak.controls.services")
    }

    private var inlineChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DastakWordmark(size: 27)
                    .foregroundStyle(.white)
                    .shadow(color:.black.opacity(0.5),radius:3,y:1)
                    .accessibilityIdentifier("dastak.wordmark")
                MarketplaceFeedbackButton(action: chooseLocation) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DELIVERING TO").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                            Text(locationLabel).font(.caption.weight(.semibold)).lineLimit(2)
                        }
                    } icon: { Image(systemName: "mappin.and.ellipse") }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .accessibilityLabel("Delivery location, \(locationLabel)")
                .accessibilityHint("Manage delivery addresses for Food and Grocery")
                .accessibilityIdentifier("dastak.location")
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    ForEach(DastakCustomerSection.allCases, id: \.self) { section in
                        MarketplaceFeedbackButton { selectSection(section) } label: {
                            Label(section.rawValue, systemImage: section.symbol)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 10)
                                .foregroundStyle(navigation.section == section ? Color.white : Color.primary)
                                .background(navigation.section == section ? MarketplaceColors.dastakAccent.color : .clear,
                                            in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(navigation.section == section ? .isSelected : [])
                        .accessibilityIdentifier("dastak.navigation.\(section.rawValue.lowercased())")
                    }
                }
                .padding(5)
                .frame(width: availableWidth < 350 ? 96 : 120)
                .marketplaceGlass(cornerRadius: 22)

                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        ForEach(DastakCustomerService.allCases, id: \.self) { service in
                            MarketplaceFeedbackButton { selectService(service) } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: service.symbol)
                                    Text(service.rawValue).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                                    if !service.isAvailable { Text("SOON").font(.system(size: 8, weight: .bold)) }
                                }
                                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(navigation.service == service ? Color.white : service.isAvailable ? Color.primary : Color.secondary)
                                .background(navigation.service == service ? MarketplaceColors.dastakAccent.color : .clear,
                                            in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .disabled(!service.isAvailable)
                            .accessibilityLabel(service.isAvailable ? service.rawValue : "\(service.rawValue), coming soon")
                            .accessibilityAddTraits(navigation.service == service ? .isSelected : [])
                            .accessibilityIdentifier("dastak.service.\(service.rawValue.lowercased())")
                        }
                    }
                    .padding(5)
                    .marketplaceGlass(cornerRadius: 22)
                    if navigation.service == .grocery { directory }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var directory: some View {
        ScrollView {
            directoryContents(expanded: false)
        }
        .frame(height: 132)
        .marketplaceGlass(cornerRadius: 16)
        .accessibilityIdentifier("dastak.directory")
    }

    private func directoryContents(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let map, map.isValid {
                ForEach(DastakCustomerNavigation.directorySections(map)) { group in
                    Text(group.label.uppercased()).font(expanded ? .headline : .caption2.weight(.bold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        ForEach(map.children(of: group.key).filter { $0.kind == "DESTINATION" }) { node in
                            MarketplaceFeedbackButton { controlSheet = nil; openDirectory(node.key) } label: {
                                HStack(spacing: 4) {
                                    Text(node.label).font(expanded ? .body : .caption.weight(navigation.directoryKey == node.key ? .bold : .regular))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.right").font(.caption2)
                                }
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .foregroundStyle(navigation.directoryKey == node.key ? MarketplaceColors.primaryActionForeground.color : Color.primary)
                                .background(navigation.directoryKey == node.key ? MarketplaceColors.dastakAccentSoft.color : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(navigation.directoryKey == node.key ? .isSelected : [])
                        }
                }
            } else { Text("The store directory will appear when categories are available.").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(8)
    }
}

private struct DastakChromeLiquidGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.marketplaceGlass(cornerRadius: 14)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .glassEffect(.clear.interactive(), in: Capsule())
                .overlay {
                    // Keep the native optical material; lift its edge over the dark ceiling.
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.14), .white.opacity(0.02), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay {
                            Capsule().strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.7), .white.opacity(0.12), .white.opacity(0.38)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.12), .white.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.75
                    )
                }
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
    }
}
