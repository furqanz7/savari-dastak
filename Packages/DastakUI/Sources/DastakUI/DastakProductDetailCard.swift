import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

/// One bounded, independently scrolling product card for both shopping roles.
struct DastakProductDetailCard<Controls: View, Action: View>: View {
    let product: DastakDetailProduct
    let products: [DastakDetailProduct]
    let select: (UUID) -> Void
    let close: () -> Void
    var isSaved = false
    var wishlistBusy = false
    var toggleWishlist: (() -> Void)?
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let action: () -> Action
    @State private var photo = 0

    private let blue = Color(red: 0.02, green: 0.32, blue: 1)

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            VStack(spacing: 12) {
                                gallery.id("product-top")
                                information
                                controls()
                                facts
                            }
                            .padding(.bottom, 16)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: product.id) { _, _ in
                            photo = 0
                            proxy.scrollTo("product-top", anchor: .top)
                        }
                    }
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product.packSize).font(.caption).foregroundStyle(.secondary)
                            Text(product.price).font(.headline.bold())
                            if let unitPrice = product.unitPrice { Text(unitPrice).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        action()
                    }
                    .padding(16)
                    .background(.white)
                    .overlay(alignment: .top) { Divider() }
                }
                .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(alignment: .top) { toolbar }
                .frame(maxWidth: 540)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 18) {
                            ForEach(products) { item in
                                Button { select(item.id) } label: {
                                    DastakProductArtwork(imageKey: item.imageKey)
                                        .frame(width: 58, height: 58)
                                        .padding(5)
                                        .background(.white.opacity(item.id == product.id ? 1 : 0.6), in: Circle())
                                        .clipShape(Circle())
                                        .overlay { Circle().stroke(.white, lineWidth: item.id == product.id ? 2 : 0).padding(-4) }
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .accessibilityLabel("View \(item.name), \(item.packSize)")
                                .accessibilityAddTraits(item.id == product.id ? .isSelected : [])
                            }
                        }
                        .padding(8)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo(product.id, anchor: .center) }
                    .onChange(of: product.id) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
                .frame(height: 84)
                .frame(maxWidth: 540)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(red: 0.37, green: 0.39, blue: 0.41).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: close) { Image(systemName: "chevron.down") }.accessibilityLabel("Close product details")
            Spacer()
            if let toggleWishlist {
                Button(action: toggleWishlist) { Image(systemName: isSaved ? "bookmark.fill" : "bookmark") }
                    .disabled(wishlistBusy)
                    .accessibilityLabel(isSaved ? "Remove from Wishlist" : "Save to Wishlist")
            }
            ShareLink(item: "\(product.name) · \(product.packSize) · \(product.price) — Dastak") { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share product")
        }
        .font(.title3)
        .buttonStyle(ProductCircleButtonStyle())
        .padding(12)
    }

    private var gallery: some View {
        VStack(spacing: 8) {
            TabView(selection: $photo) {
                ForEach(Array(product.images.enumerated()), id: \.offset) { index, key in
                    DastakProductArtwork(imageKey: key, detail: true)
                        .padding(.horizontal, 22)
                        .tag(index)
                }
            }
#if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
#endif
            .frame(height: 285)
            if product.images.count > 1 {
                HStack(spacing: 3) {
                    ForEach(product.images.indices, id: \.self) { index in
                        Button { withAnimation { photo = index } } label: {
                            Circle().fill(photo == index ? blue : Color.gray.opacity(0.3)).frame(width: 5, height: 5).frame(width: 22, height: 22)
                        }.accessibilityLabel("View photo \(index + 1)")
                    }
                }
            }
        }
        .padding(.top, 52)
        .padding(.bottom, 6)
        .background(Color(red: 0.975, green: 0.975, blue: 0.983))
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let brand = product.brand { Text(brand).font(.subheadline.bold()).foregroundStyle(blue) }
            Text(product.name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            if let description = product.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Pack: \(product.packSize)").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
            let packs = products.filter { product.sameFamily(as: $0) }
            if packs.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(packs) { pack in
                            Button { select(pack.id) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pack.packSize).font(.subheadline.bold())
                                    Text(pack.price).font(.subheadline.bold())
                                    if let unit = pack.unitPrice { Text(unit).font(.caption2).foregroundStyle(.secondary) }
                                }
                                .frame(minWidth: 90, alignment: .leading).padding(12)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .overlay { RoundedRectangle(cornerRadius: 14).stroke(pack.id == product.id ? blue : .gray.opacity(0.25), lineWidth: pack.id == product.id ? 2 : 1) }
                            }.buttonStyle(.plain).accessibilityAddTraits(pack.id == product.id ? .isSelected : [])
                        }
                    }.padding(3)
                }.scrollIndicators(.hidden)
            } else {
                HStack { Text(product.price).font(.headline); if let list = product.listPrice { Text(list).font(.caption).strikethrough().foregroundStyle(.secondary) } }
                if let unit = product.unitPrice { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }.productInfoSurface()
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Product information").font(.headline)
            ForEach(product.facts, id: \.label) { fact in
                HStack(alignment: .top) { Text(fact.label).foregroundStyle(.secondary); Spacer(); Text(fact.value).multilineTextAlignment(.trailing) }.font(.subheadline)
                Divider()
            }
            Text("Refer to the packaging for the most up-to-date ingredients, allergens and usage information.")
                .font(.caption).foregroundStyle(.secondary)
        }.productInfoSurface()
    }
}

struct DastakDetailProduct: Identifiable {
    struct Fact { let label: String; let value: String }
    let id: UUID
    let name: String
    let brand: String?
    let variant: String?
    let packSize: String
    let description: String?
    let imageKey: String?
    let gallery: [String]
    let pricePaise: Int
    let listPricePaise: Int
    let quantityValue: Double?
    let quantityUnit: String?
    let packCount: Int?
    let facts: [Fact]
    var price: String { DastakFormatting.money(Money(paise: pricePaise)) }
    var listPrice: String? { listPricePaise > pricePaise ? DastakFormatting.money(Money(paise: listPricePaise)) : nil }
    var images: [String?] {
        var seen = Set<String>()
        let keys = ([imageKey].compactMap { $0 } + gallery).filter { seen.insert($0).inserted }
        return keys.isEmpty ? [nil] : keys.map(Optional.some)
    }
    var unitPrice: String? {
        guard let value = quantityValue, value > 0, let unit = quantityUnit,
              ["kg", "g", "l", "ml"].contains(unit), (packCount ?? 1) > 0 else { return nil }
        let base = value * (["kg", "l"].contains(unit) ? 1000 : 1) * Double(packCount ?? 1)
        return DastakFormatting.money(Money(paise: Int((Double(pricePaise) * 100 / base).rounded()))) + "/100 " + (["kg", "g"].contains(unit) ? "g" : "ml")
    }
    func sameFamily(as other: Self) -> Bool {
        func normalized(_ item: Self) -> String {
            item.name.lowercased().replacingOccurrences(of: item.packSize.lowercased(), with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return id == other.id || (brand != nil && brand == other.brand && variant == other.variant && normalized(self) == normalized(other))
    }
    init(_ sku: DastakV1CatalogueSKU) {
        id = sku.id; name = sku.name; brand = sku.brand?.name; variant = sku.variant; packSize = sku.packSize
        description = sku.description; imageKey = sku.imageKey; gallery = sku.galleryImageKeys ?? []
        pricePaise = sku.sellingPricePaise; listPricePaise = sku.listPricePaise
        quantityValue = sku.quantityValue.map { NSDecimalNumber(decimal: $0).doubleValue }; quantityUnit = sku.quantityUnit; packCount = sku.packCount
        facts = [("Pack size", sku.packSize), ("Manufacturer", sku.manufacturerName), ("Origin", sku.countryOfOriginCode), ("Diet", sku.dietType), ("Barcode", sku.barcode)].compactMap { label, value in value.map { Fact(label: label, value: $0) } }
    }
    init(_ sku: DastakV1MerchantCatalogueSnapshot.SKU) {
        id = sku.id; name = sku.name; brand = sku.brandName; variant = sku.variant; packSize = sku.packSize
        description = sku.description; imageKey = sku.imageKey; gallery = sku.galleryImageKeys
        pricePaise = sku.sellingPricePaise; listPricePaise = sku.listPricePaise
        quantityValue = sku.quantityValue; quantityUnit = sku.quantityUnit; packCount = sku.packCount
        facts = [("Pack size", sku.packSize), ("Variant", sku.variant), ("Diet", sku.dietType)].compactMap { label, value in value.map { Fact(label: label, value: $0) } }
    }
}

private struct ProductCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color(white: 0.3)).frame(width: 42, height: 42)
            .background(Color(white: configuration.isPressed ? 0.88 : 0.96).opacity(0.95), in: Circle())
    }
}

struct DastakCustomerProductDetailView: View {
    @ObservedObject var model: DastakCustomerModel
    let products: [DastakV1CatalogueSKU]
    @State private var selectedID: UUID
    @Environment(\.dismiss) private var dismiss

    init(model: DastakCustomerModel, initial: DastakV1CatalogueSKU, products: [DastakV1CatalogueSKU]) {
        self.model = model
        self.products = products.contains(where: { $0.id == initial.id }) ? products : [initial] + products
        _selectedID = State(initialValue: initial.id)
    }

    var body: some View {
        if let sku = products.first(where: { $0.id == selectedID }) {
            let count = model.cart.entries.first { $0.product.id == sku.id }?.quantity ?? 0
            DastakProductDetailCard(
                product: DastakDetailProduct(sku),
                products: products.filter { $0.categoryID == sku.categoryID }.map(DastakDetailProduct.init),
                select: { selectedID = $0 }, close: { dismiss() },
                isSaved: model.isWishlisted(kind: .retailSKU, itemID: sku.id),
                wishlistBusy: model.wishlistUpdatingIDs.contains(sku.id),
                toggleWishlist: { Task { await model.toggleWishlist(kind: .retailSKU, itemID: sku.id) } }
            ) {
                EmptyView()
            } action: {
                HStack(spacing: 12) {
                    if count > 0 {
                        Button { model.decrementCartItem(sku.id) } label: { Image(systemName: "minus").frame(width: 36, height: 46) }.accessibilityLabel("Remove one \(sku.name)")
                        Text("\(count)").font(.headline).accessibilityLabel("\(count) in basket")
                        Button { model.addToCart(sku) } label: { Image(systemName: "plus").frame(width: 36, height: 46) }.disabled(count >= DastakCart.maximumQuantity).accessibilityLabel("Add one \(sku.name)")
                    } else {
                        Button { model.addToCart(sku) } label: { Text("ADD").font(.headline.bold()).frame(width: 130, height: 46) }.accessibilityLabel("Add \(sku.name) to basket")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color(red: 0.02, green: 0.32, blue: 1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

extension View {
    func productInfoSurface() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.gray.opacity(0.1)) }
            .padding(.horizontal, 14)
    }
}

struct DastakMerchantProductDetailView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var selectedID: UUID
    @State private var stock: String
    @State private var stockVersion: Int
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss

    init(model: DastakMerchantModel, initial: DastakV1MerchantCatalogueSnapshot.SKU) {
        self.model = model
        _selectedID = State(initialValue: initial.id)
        _stock = State(initialValue: initial.stockQuantity.map(String.init) ?? "")
        _stockVersion = State(initialValue: initial.selectionVersion)
    }

    var body: some View {
        if let snapshot = model.canonicalCatalogue, let sku = snapshot.skus.first(where: { $0.id == selectedID }) {
            DastakProductDetailCard(product: DastakDetailProduct(sku),
                products: snapshot.skus.filter { $0.categoryID == sku.categoryID }.map(DastakDetailProduct.init),
                select: { id in
                    guard !model.isBusy, let next = snapshot.skus.first(where: { $0.id == id }) else { return }
                    selectedID = id; stock = next.stockQuantity.map(String.init) ?? ""; stockVersion = next.selectionVersion; saved = false
                }, close: { dismiss() }
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available stock").font(.headline)
                    Text("\(snapshot.branch.branchName) · units of \(sku.packSize)").font(.caption).foregroundStyle(.secondary)
                    Text("Available: \(sku.stockQuantity.map(String.init) ?? "Not set") · Reserved for orders: \(sku.stockReservedQuantity ?? 0)").font(.caption)
                    HStack {
                        Button { stock = String(max(min(max(Int(stock) ?? 0, 0), 1_000_000) - 1, 0)); saved = false } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("Decrease stock count")
                        TextField("Not set", text: $stock).multilineTextAlignment(.center).textFieldStyle(.roundedBorder)
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                            .accessibilityLabel("Stock quantity")
                            .onChange(of: stock) { _, _ in saved = false }
                        Button { stock = String(min(min(max(Int(stock) ?? 0, 0), 1_000_000) + 1, 1_000_000)); saved = false } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Increase stock count")
                    }.disabled(model.isBusy)
                    Text("Accepted orders reduce available stock automatically. Cancelled reservations return to stock. Enter only unreserved units when restocking or correcting a count; do not deduct these orders again. Zero makes the product unavailable.").font(.caption).foregroundStyle(.secondary)
                    if stockVersion != sku.selectionVersion {
                        Text("The stock count has changed.").font(.caption)
                        Button("Use latest stock count") {
                            stock = sku.stockQuantity.map(String.init) ?? ""
                            stockVersion = sku.selectionVersion
                            saved = false
                        }.disabled(model.isBusy)
                    }
                    if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    if saved { Label("Stock count saved", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                }.productInfoSurface()
            } action: {
                Button {
                    guard let quantity = Int(stock) else { return }
                    Task { saved = await model.saveStockCount(sku, quantity: quantity) }
                } label: {
                    Text(model.isBusy ? "Saving…" : "Save stock").font(.headline.bold()).frame(minWidth: 130, minHeight: 46)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Color(red: 0.02, green: 0.32, blue: 1), in: RoundedRectangle(cornerRadius: 12))
                .disabled(model.isBusy || stockVersion != sku.selectionVersion || sku.catalogueStatus != "ACTIVE" || Int(stock).map { !(0...(1_000_000 - (sku.stockReservedQuantity ?? 0))).contains($0) } != false)
            }
        }
    }
}
