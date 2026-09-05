import Foundation
import MarketplaceDesignSystem
import MarketplaceInfrastructure
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct DastakArtworkRequest: Hashable, Sendable {
    let thumbnailURL: URL
    let originalURL: URL

    var candidateURLs: [URL] {
        thumbnailURL == originalURL ? [thumbnailURL] : [thumbnailURL, originalURL]
    }
}

enum DastakArtworkURLFactory {
    static func request(
        for imageKey: String?,
        baseURLString: String?,
        pixelSize: Int = 512
    ) -> DastakArtworkRequest? {
        guard let imageKey,
              let baseURLString,
              !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let segments = imageKey.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty,
              segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") })
        else { return nil }

        var allowedPathCharacters = CharacterSet.urlPathAllowed
        allowedPathCharacters.remove(charactersIn: "/?#")
        let encoded = segments.compactMap {
            String($0).addingPercentEncoding(withAllowedCharacters: allowedPathCharacters)
        }
        guard encoded.count == segments.count else { return nil }

        let base = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = encoded.joined(separator: "/")
        guard let originalURL = URL(
            string: base + "/storage/v1/object/public/dastak-catalogue/" + path
        ), var thumbnailComponents = URLComponents(
            string: base + "/storage/v1/render/image/public/dastak-catalogue/" + path
        ) else { return nil }

        let dimension = min(max(pixelSize, 128), 1_024)
        thumbnailComponents.queryItems = [
            URLQueryItem(name: "width", value: String(dimension)),
            URLQueryItem(name: "height", value: String(dimension)),
            URLQueryItem(name: "resize", value: "contain"),
            URLQueryItem(name: "quality", value: "72"),
        ]
        guard let thumbnailURL = thumbnailComponents.url else { return nil }
        return DastakArtworkRequest(thumbnailURL: thumbnailURL, originalURL: originalURL)
    }
}

enum DastakCatalogueSymbol {
    static func symbol(for value: String) -> String {
        let value = value.lowercased()
        if value.contains("pharmacy") || value.contains("medicine") || value.contains("health") || value.contains("first-aid") {
            return "cross.case.fill"
        }
        if value.contains("paan") || value.contains("betel") || value.contains("mukhwas") {
            return "leaf.fill"
        }
        if value.contains("fruit") || value.contains("vegetable") || value.contains("produce") || value.contains("herb") {
            return "leaf.fill"
        }
        if value.contains("dairy") || value.contains("milk") || value.contains("beverage") || value.contains("drink") {
            return "takeoutbag.and.cup.and.straw.fill"
        }
        if value.contains("baby") || value.contains("care") || value.contains("beauty") {
            return "sparkles"
        }
        if value.contains("home") || value.contains("kitchen") || value.contains("clean") {
            return "house.fill"
        }
        if value.contains("pet") { return "pawprint.fill" }
        if value.contains("toy") || value.contains("game") { return "gamecontroller.fill" }
        if value.contains("electronic") || value.contains("mobile") { return "desktopcomputer" }
        if value.contains("hardware") || value.contains("automotive") { return "wrench.and.screwdriver.fill" }
        if value.contains("food") || value.contains("snack") || value.contains("grocery") { return "basket.fill" }
        return "shippingbox.fill"
    }
}

private actor DastakArtworkDataStore {
    static let shared = DastakArtworkDataStore()

    private var cachedData: [URL: Data] = [:]
    private var cachedByteCount = 0
    private var inFlight: [DastakArtworkRequest: Task<Data?, Never>] = [:]
    private let maximumCachedBytes = 64 * 1_024 * 1_024

    func data(for request: DastakArtworkRequest) async -> Data? {
        if let data = cachedData[request.thumbnailURL] { return data }
        if let task = inFlight[request] { return await task.value }

        let task = Task<Data?, Never> {
            for candidateURL in request.candidateURLs {
                if let data = await Self.download(candidateURL) {
                    return data
                }
            }
            return nil
        }
        inFlight[request] = task
        let data = await task.value
        inFlight[request] = nil
        if let data {
            cache(data, for: request.thumbnailURL)
        }
        return data
    }

    func prefetch(_ requests: [DastakArtworkRequest]) async {
        var seen = Set<DastakArtworkRequest>()
        let uniqueRequests = Array(requests.filter { seen.insert($0).inserted }.prefix(64))
        for start in stride(from: 0, to: uniqueRequests.count, by: 8) {
            let end = min(start + 8, uniqueRequests.count)
            await withTaskGroup(of: Void.self) { group in
                for request in uniqueRequests[start..<end] {
                    group.addTask { _ = await self.data(for: request) }
                }
            }
        }
    }

    private static func download(_ url: URL) async -> Data? {
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }
            var urlRequest = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 12
            )
            urlRequest.setValue("image/webp,image/*", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                guard let response = response as? HTTPURLResponse else { return nil }
                if (200..<300).contains(response.statusCode),
                   !data.isEmpty,
                   response.mimeType?.lowercased().hasPrefix("image/") != false {
                    return data
                }
                guard (response.statusCode == 429 || (500..<600).contains(response.statusCode)), attempt < 2 else {
                    return nil
                }
            } catch {
                guard attempt < 2 else { return nil }
            }
            let delay = attempt == 0 ? 150_000_000 : 450_000_000
            try? await Task.sleep(nanoseconds: UInt64(delay))
        }
        return nil
    }

    private func cache(_ data: Data, for url: URL) {
        guard data.count <= maximumCachedBytes else { return }
        if let previous = cachedData.updateValue(data, forKey: url) {
            cachedByteCount -= previous.count
        }
        cachedByteCount += data.count
        while cachedByteCount > maximumCachedBytes, let oldestURL = cachedData.keys.first {
            if let removed = cachedData.removeValue(forKey: oldestURL) {
                cachedByteCount -= removed.count
            }
        }
    }
}

@MainActor
private final class DastakArtworkViewModel: ObservableObject {
    @Published private(set) var image: Image?
    private var representedRequest: DastakArtworkRequest?

    func load(_ request: DastakArtworkRequest?) async {
        guard representedRequest != request || image == nil else { return }
        representedRequest = request
        image = nil
        guard let request,
              let data = await DastakArtworkDataStore.shared.data(for: request),
              representedRequest == request
        else {
            return
        }
#if canImport(UIKit)
        if let platformImage = UIImage(data: data) {
            image = Image(uiImage: platformImage)
        }
#elseif canImport(AppKit)
        if let platformImage = NSImage(data: data) {
            image = Image(nsImage: platformImage)
        }
#endif
    }
}

struct DastakEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                    .frame(maxWidth: 320)
            }
        }
    }
}

struct DastakRefreshNotice: View {
    let failure: DastakCustomerRefreshFailure
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: failure.symbol)
                .font(.title3)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(failure.title)
                    .font(.subheadline.bold())
                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: MarketplaceSpacing.small)
            Text("Pull to refresh")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
        }
        .padding(MarketplaceSpacing.compact)
        .marketplaceFlatSurface()
    }
}

struct DastakProductArtwork: View {
    private let kind: CatalogueKind?
    private let customSymbol: String?
    private let imageKey: String?

    init(kind: CatalogueKind) {
        self.kind = kind
        customSymbol = nil
        imageKey = nil
    }

    init(symbol: String) {
        kind = nil
        customSymbol = symbol
        imageKey = nil
    }

    init(imageKey: String?, fallbackSymbol: String = "basket") {
        kind = nil
        customSymbol = fallbackSymbol
        self.imageKey = imageKey
    }

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var loader = DastakArtworkViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    MarketplaceColors.accent(for: colorScheme).opacity(colorScheme == .dark ? 0.13 : 0.07),
                    Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.018),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let image = loader.image {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .transition(.opacity)
            } else {
                fallback
                    .opacity(artworkRequest == nil ? 1 : 0.58)
            }
        }
        .aspectRatio(1.18, contentMode: .fit)
        .clipShape(
            RoundedRectangle(
                cornerRadius: MarketplaceMetrics.compactCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MarketplaceMetrics.compactCornerRadius,
                style: .continuous
            )
            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.045), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
        .task(id: artworkRequest) {
            await loader.load(artworkRequest)
        }
        .animation(.easeOut(duration: 0.16), value: loader.image != nil)
    }

    static func prefetch(imageKeys: [String]) async {
        await DastakArtworkDataStore.shared.prefetch(imageKeys.compactMap(artworkRequest(for:)))
    }

    private var fallback: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(MarketplaceColors.accent(for: colorScheme))
    }

    private var artworkRequest: DastakArtworkRequest? {
        Self.artworkRequest(for: imageKey)
    }

    private static func artworkRequest(for imageKey: String?) -> DastakArtworkRequest? {
        DastakArtworkURLFactory.request(
            for: imageKey,
            baseURLString: Bundle.main.object(forInfoDictionaryKey: "MarketplaceSupabaseURL") as? String
        )
    }

    private var symbol: String {
        if let customSymbol { return customSymbol }
        return switch kind {
        case .general, .none: "shippingbox"
        case .otcMedicine, .prescriptionMedicine: "cross.case"
        case .paanCorner: "checkmark.shield"
        }
    }
}

struct DastakQuantityControl: View {
    let quantity: Int
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: decrement) {
                Image(systemName: "minus")
            }
            .accessibilityLabel("Remove one")

            Text(quantity.formatted())
                .font(.subheadline.monospacedDigit().bold())
                .frame(minWidth: 32)

            Button(action: increment) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add one")
        }
        .buttonStyle(.plain)
        .frame(minHeight: MarketplaceMetrics.minimumTouchTarget)
        .padding(.horizontal, MarketplaceSpacing.small)
        .background(.thinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: MarketplaceMetrics.controlCornerRadius,
                style: .continuous
            )
        )
    }
}

struct DastakStatusPill: View {
    let text: String
    var emphasis = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, MarketplaceSpacing.compact)
            .frame(minHeight: 30)
            .foregroundStyle(
                emphasis
                    ? MarketplaceColors.accent(for: colorScheme)
                    : MarketplaceColors.secondaryText(for: colorScheme)
            )
            .background(
                emphasis
                    ? MarketplaceColors.accent(for: colorScheme).opacity(0.12)
                    : MarketplaceColors.surface(for: colorScheme)
            )
            .clipShape(Capsule())
    }
}

struct DastakLoadingOverlay: View {
    let title: String

    var body: some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            ProgressView()
            Text(title)
                .font(.subheadline)
        }
        .padding(.horizontal, MarketplaceSpacing.medium)
        .frame(minHeight: 48)
        .marketplaceGlass(cornerRadius: MarketplaceMetrics.controlCornerRadius)
    }
}

struct DastakApplicationProgress: View {
    let currentStep: Int
    private let steps = ["Account", "Application", "Review"]

    init(currentStep: Int = 2) {
        self.currentStep = currentStep
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let step = index + 1
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(step <= currentStep
                                    ? MarketplaceColors.dastakAccent.color
                                    : MarketplaceColors.dastakSurface.color)
                                .overlay {
                                    Circle().stroke(
                                        step <= currentStep
                                            ? MarketplaceColors.dastakAccent.color
                                            : MarketplaceColors.dividerDark.color,
                                        lineWidth: 1
                                    )
                                }
                            if step < currentStep {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(MarketplaceColors.dastakIconBackground.color)
                            } else {
                                Text(step.formatted())
                                    .font(.caption.bold())
                                    .foregroundStyle(step == currentStep
                                        ? MarketplaceColors.dastakIconBackground.color
                                        : .secondary)
                            }
                        }
                        .frame(width: 28, height: 28)

                        if step < steps.count {
                            Rectangle()
                                .fill(MarketplaceColors.dividerDark.color)
                                .frame(height: 1)
                                .padding(.horizontal, 6)
                        }
                    }
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(step <= currentStep ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep) of \(steps.count), \(steps[currentStep - 1])")
    }
}
