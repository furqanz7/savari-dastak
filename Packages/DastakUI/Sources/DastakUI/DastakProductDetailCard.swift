import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

private struct ProductDetailPalette {
    let dark: Bool
    var ink: Color { dark ? Color(white: 0.96) : Color(red: 0.12, green: 0.14, blue: 0.18) }
    var secondary: Color { dark ? Color(white: 0.68) : Color(red: 0.39, green: 0.42, blue: 0.47) }
    var surface: Color { dark ? Color(red: 0.12, green: 0.13, blue: 0.16) : .white }
    var canvas: Color { dark ? Color(red: 0.08, green: 0.09, blue: 0.11) : Color(red: 0.96, green: 0.97, blue: 0.985) }
    var line: Color { dark ? .white.opacity(0.1) : .black.opacity(0.075) }
    var accent: Color { dark ? Color(red: 0.48, green: 0.67, blue: 1) : Color(red: 0.02, green: 0.30, blue: 0.92) }
    static let action = Color(red: 0.02, green: 0.32, blue: 1)
}

/// One bounded, independently scrolling product card for both shopping roles.
struct DastakProductDetailCard<Controls: View, Action: View>: View {
    let product: DastakDetailProduct
    let products: [DastakDetailProduct]
    let select: (UUID) -> Void
    let close: () -> Void
    var isSaved = false
    var wishlistBusy = false
    var toggleWishlist: (() -> Void)?
    var openCart: (() -> Void)?
    var cartCount = 0
    var basketModel: DastakCustomerModel?
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let action: () -> Action
    @Environment(\.colorScheme) private var colorScheme
    @State private var photo = 0
    private var palette: ProductDetailPalette { .init(dark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                toolbar
                ScrollView(.vertical) {
                    VStack(spacing: 12) {
                        gallery(height: max(180, geometry.size.height * 0.46))
                        information
                        controls()
                        facts
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.packSize).font(.caption).foregroundStyle(palette.secondary)
                        HStack(spacing: 5) {
                            Text(product.price).font(.title3.bold()).foregroundStyle(palette.ink)
                            if let list = product.listPrice {
                                Text(list).font(.caption).strikethrough().foregroundStyle(palette.secondary)
                            }
                        }
                        if let unitPrice = product.unitPrice {
                            Text(unitPrice).font(.caption2).foregroundStyle(palette.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    action()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(palette.surface)
                .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
            }
            .background(palette.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .accessibilityIdentifier("product-detail-card-\(product.id)")
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            MarketplaceFeedbackButton(action: close) { Image(systemName: "chevron.down") }.accessibilityLabel("Close product details")
            Spacer()
            if let toggleWishlist {
                MarketplaceFeedbackButton(action: toggleWishlist) { Image(systemName: isSaved ? "bookmark.fill" : "bookmark") }
                    .disabled(wishlistBusy)
                    .accessibilityLabel(isSaved ? "Remove from Wishlist" : "Save to Wishlist")
            }
            if let basketModel {
                DastakBasketPickupButton(model: basketModel, service: .grocery)
            } else if let openCart {
                MarketplaceFeedbackButton(action: openCart) {
                    Image(systemName: "cart")
                        .overlay(alignment: .topTrailing) {
                            if cartCount > 0 {
                                Text(cartCount.formatted()).font(.system(size: 10, weight: .bold))
                                    .padding(3).background(palette.accent, in: Circle())
                                    .offset(x: 9, y: -9)
                            }
                        }
                }
                .accessibilityLabel("Open Grocery cart, \(cartCount) items")
            }
            ShareLink(item: "\(product.name) · \(product.packSize) · \(product.price) — Dastak") { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share product")
        }
        .font(.system(size: 19, weight: .regular))
        .buttonStyle(ProductCircleButtonStyle())
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func gallery(height: CGFloat) -> some View {
        VStack(spacing: 2) {
            // Photo arrows/dots browse images; a card swipe always changes the product.
            GeometryReader { bounds in
                DastakProductArtwork(imageKey: product.images[min(photo, product.images.count - 1)], detail: true)
                    .id(product.id.uuidString + ":\(photo)")
                    .frame(width: bounds.size.width, height: bounds.size.height)
            }
                .frame(height: height)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .accessibilityLabel("Photo \(photo + 1) of \(product.images.count), \(product.name)")
                .accessibilityHidden(false)
            if product.images.count > 1 {
                HStack(spacing: 2) {
                    MarketplaceFeedbackButton { photo = (photo - 1 + product.images.count) % product.images.count } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 32)
                    }.accessibilityLabel("Previous product photo")
                    ForEach(product.images.indices, id: \.self) { position in
                        MarketplaceFeedbackButton { photo = position } label: {
                            Capsule().fill(photo == position ? palette.accent : palette.secondary.opacity(0.3))
                                .frame(width: photo == position ? 14 : 5, height: 5).frame(width: 24, height: 32)
                        }.accessibilityLabel("View photo \(position + 1)")
                            .accessibilityAddTraits(photo == position ? .isSelected : [])
                    }
                    MarketplaceFeedbackButton { photo = (photo + 1) % product.images.count } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 32)
                    }.accessibilityLabel("Next product photo")
                }.font(.caption).buttonStyle(.plain).foregroundStyle(palette.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let brand = product.brand {
                Text(brand).font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent)
            }
            Text(product.name).font(.system(size: 19, weight: .semibold)).tracking(-0.4)
                .foregroundStyle(palette.ink).fixedSize(horizontal: false, vertical: true)
            if let description = product.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(product.packSize).font(.subheadline.weight(.medium)).foregroundStyle(palette.secondary).padding(.top, 4)
            let packs = products.filter { product.sameFamily(as: $0) }
            if packs.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(packs) { pack in
                            MarketplaceFeedbackButton(haptic: .selection) { select(pack.id) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pack.packSize).font(.subheadline.bold())
                                    Text(pack.price).font(.subheadline.bold())
                                    if let unit = pack.unitPrice { Text(unit).font(.caption2).foregroundStyle(palette.secondary) }
                                }
                                .foregroundStyle(palette.ink)
                                .frame(minWidth: 90, alignment: .leading).padding(12)
                                .background(pack.id == product.id ? palette.accent.opacity(0.07) : palette.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay { RoundedRectangle(cornerRadius: 14).stroke(pack.id == product.id ? palette.accent : palette.line, lineWidth: pack.id == product.id ? 2 : 1) }
                            }.buttonStyle(.plain).accessibilityAddTraits(pack.id == product.id ? .isSelected : [])
                        }
                    }.padding(3)
                }
                .scrollIndicators(.hidden)
            } else {
                HStack(spacing: 8) {
                    Text(product.price).font(.title3.bold())
                    if let list = product.listPrice { Text(list).font(.subheadline).strikethrough().foregroundStyle(palette.secondary) }
                }.foregroundStyle(palette.ink)
                if let unit = product.unitPrice { Text(unit).font(.caption).foregroundStyle(palette.secondary) }
            }
        }.productInfoSurface()
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Product information").font(.headline).foregroundStyle(palette.ink)
            ForEach(product.facts, id: \.label) { fact in
                HStack(alignment: .top) {
                    Text(fact.label).foregroundStyle(palette.secondary)
                    Spacer(minLength: 12)
                    Text(fact.value).foregroundStyle(palette.ink).multilineTextAlignment(.trailing)
                }.font(.subheadline)
                Rectangle().fill(palette.line).frame(height: 1)
            }
            Text("Refer to the packaging for the most up-to-date ingredients, allergens and usage information.")
                .font(.caption).foregroundStyle(palette.secondary)
        }.productInfoSurface()
    }
}

struct DastakDetailProduct: Identifiable {
    struct Fact { let label: String; let value: String }
    let id: UUID
    let name: String
    let brand: String?
    let variant: String?
    let familyScope: String
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
        let name = DastakGroceryPresentation.normalizedName(name, packSize: packSize)
        return id == other.id || (brand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            brand == other.brand && variant == other.variant && familyScope == other.familyScope && !name.isEmpty &&
            name == DastakGroceryPresentation.normalizedName(other.name, packSize: other.packSize))
    }
    init(_ sku: DastakV1CatalogueSKU) {
        id = sku.id; name = sku.name; brand = sku.brand?.name; variant = sku.variant; packSize = sku.packSize
        familyScope = "\(sku.categoryID)|\(sku.subcategoryID)"
        description = sku.description; imageKey = sku.imageKey; gallery = sku.galleryImageKeys ?? []
        pricePaise = sku.sellingPricePaise; listPricePaise = sku.listPricePaise
        quantityValue = sku.quantityValue.map { NSDecimalNumber(decimal: $0).doubleValue }; quantityUnit = sku.quantityUnit; packCount = sku.packCount
        facts = [("Pack size", sku.packSize), ("Manufacturer", sku.manufacturerName), ("Origin", sku.countryOfOriginCode), ("Diet", sku.dietType), ("Barcode", sku.barcode)].compactMap { label, value in value.map { Fact(label: label, value: $0) } }
    }
    init(_ sku: DastakV1MerchantCatalogueSnapshot.SKU) {
        id = sku.id; name = sku.name; brand = sku.brandName; variant = sku.variant; packSize = sku.packSize
        familyScope = "\(sku.categoryID)|\(sku.subcategoryID)"
        description = sku.description; imageKey = sku.imageKey; gallery = sku.galleryImageKeys
        pricePaise = sku.sellingPricePaise; listPricePaise = sku.listPricePaise
        quantityValue = sku.quantityValue; quantityUnit = sku.quantityUnit; packCount = sku.packCount
        facts = [("Pack size", sku.packSize), ("Variant", sku.variant), ("Diet", sku.dietType)].compactMap { label, value in value.map { Fact(label: label, value: $0) } }
    }
}

private struct ProductCircleButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        let palette = ProductDetailPalette(dark: colorScheme == .dark)
        configuration.label.foregroundStyle(palette.ink).frame(width: 44, height: 44)
            .background(palette.surface.opacity(configuration.isPressed ? 0.6 : 0.85), in: Circle())
    }
}

struct DastakCustomerProductDetailView: View {
    @ObservedObject var model: DastakCustomerModel
    let products: [DastakV1CatalogueSKU]
    @State private var deck: DastakGroceryPresentation.DetailDeck
    let close: () -> Void
    let openCart: () -> Void

    init(model: DastakCustomerModel, initial: DastakV1CatalogueSKU, products: [DastakV1CatalogueSKU], close: @escaping () -> Void, openCart: @escaping () -> Void) {
        self.model = model
        let categoryProducts = products.filter { $0.categoryID == initial.categoryID }
        self.products = categoryProducts.contains(where: { $0.id == initial.id }) ? categoryProducts : [initial] + categoryProducts
        self.close = close
        self.openCart = openCart
        _deck = State(initialValue: DastakGroceryPresentation.DetailDeck(initial: initial, products: self.products))
    }

    var body: some View {
        DastakProductDetailCarousel(products: deck.families.map { DastakDetailProduct($0.product) }, selectedID: $deck.selectedFamilyID) { id, _ in
            if let sku = deck.selectedProduct(in: id) {
                DastakCustomerProductPage(model: model, sku: sku, products: products,
                    select: { deck.selectPack($0, in: id) }, close: close, openCart: openCart)
            }
        }
        .dastakBasketExperience(model: model, service: .grocery, openCart: openCart)
    }
}

private struct DastakCustomerProductPage: View {
    @ObservedObject var model: DastakCustomerModel
    let sku: DastakV1CatalogueSKU
    let products: [DastakV1CatalogueSKU]
    let select: (UUID) -> Void
    let close: () -> Void
    let openCart: () -> Void

    var body: some View {
            let count = model.baskets[.grocery].entries.first { $0.product.id == sku.id }?.quantity ?? 0
            let stock = model.groceryStockQuantity(sku.id)
            let isOutOfStock = stock == 0
            DastakProductDetailCard(
                product: DastakDetailProduct(sku),
                products: products.filter { $0.categoryID == sku.categoryID }.map(DastakDetailProduct.init),
                select: select, close: close,
                isSaved: model.isWishlisted(kind: .retailSKU, itemID: sku.id),
            wishlistBusy: model.wishlistChangeDisabled(sku.id),
                toggleWishlist: { Task { await model.toggleWishlist(kind: .retailSKU, itemID: sku.id) } },
                openCart: openCart, cartCount: model.baskets[.grocery].itemCount, basketModel: model
            ) {
                EmptyView()
            } action: {
                HStack(spacing: 12) {
                    if isOutOfStock {
                        VStack(spacing: 4) {
                            MarketplaceFeedbackButton {} label: {
                                Text(DastakGroceryPresentation.purchaseTitle(stockQuantity: stock)).font(.subheadline.weight(.semibold))
                                    .frame(width: 130, height: 46)
                            }
                            .disabled(true)
                            .accessibilityLabel("\(sku.name), \(sku.packSize), Out of stock")
                            if count > 0 {
                                HStack {
                                    MarketplaceFeedbackButton { model.decrementCartItem(sku.id) } label: {
                                        Image(systemName: "minus").frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }.accessibilityLabel("Remove one \(sku.name)")
                                    Text("\(count)").font(.headline).accessibilityLabel("\(count) in basket")
                                }
                            }
                        }
                    } else if count > 0 {
                        MarketplaceFeedbackButton { model.decrementCartItem(sku.id) } label: {
                            Image(systemName: "minus").frame(width: 44, height: 46)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove one \(sku.name)")
                        .accessibilityIdentifier("grocery.detail.minus.\(sku.id)")
                        Text("\(count)").font(.headline).accessibilityLabel("\(count) in basket")
                        MarketplaceFeedbackButton { model.addShoppingProduct(sku) } label: {
                            Image(systemName: "plus").frame(width: 44, height: 46)
                                .contentShape(Rectangle())
                        }
                        .disabled(count >= DastakCart.maximumQuantity || model.groceryAddIssue(sku.id) != nil)
                        .accessibilityLabel("Add one \(sku.name)")
                        .accessibilityIdentifier("grocery.detail.plus.\(sku.id)")
                    } else {
                        MarketplaceFeedbackButton { model.addShoppingProduct(sku) } label: {
                            Text(DastakGroceryPresentation.purchaseTitle(stockQuantity: stock)).font(.headline.bold())
                                .frame(width: 130, height: 46)
                                .contentShape(Rectangle())
                        }.disabled(model.groceryAddIssue(sku.id) != nil).accessibilityLabel("Add \(sku.name) to basket")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(isOutOfStock ? Color.secondary.opacity(0.25) : Color(red: 0.02, green: 0.32, blue: 1), in: RoundedRectangle(cornerRadius: 12))
            }
            .dastakBasketAnchor(DastakBasketService.grocery.itemAnchor(sku.id))
    }
}

extension View {
    func productInfoSurface() -> some View {
        modifier(ProductInfoSurface())
    }
}

private struct ProductInfoSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let palette = ProductDetailPalette(dark: colorScheme == .dark)
        content.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .foregroundStyle(palette.ink)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(palette.line) }
            .padding(.horizontal, 12)
    }
}

private struct ProductStockButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        let palette = ProductDetailPalette(dark: colorScheme == .dark)
        configuration.label
            .foregroundStyle(isEnabled ? .white : palette.secondary)
            .frame(minWidth: 126, minHeight: 48)
            .background(isEnabled ? ProductDetailPalette.action : palette.canvas, in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(isEnabled ? .clear : palette.line) }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct DastakMerchantProductDetailView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var selectedID: UUID
    let categoryID: UUID
    let close: () -> Void

    init(model: DastakMerchantModel, initial: DastakV1MerchantCatalogueSnapshot.SKU, close: @escaping () -> Void) {
        self.model = model
        self.categoryID = initial.categoryID
        self.close = close
        _selectedID = State(initialValue: initial.id)
    }

    var body: some View {
        if let snapshot = model.canonicalCatalogue {
            let products = snapshot.skus.filter { $0.categoryID == categoryID }
            DastakProductDetailCarousel(products: products.map(DastakDetailProduct.init), selectedID: $selectedID,
                navigationDisabled: model.isBusy) { id, select in
                if let sku = products.first(where: { $0.id == id }) {
                    DastakMerchantProductPage(model: model, initial: sku, select: select, close: close)
                }
            }
        }
    }
}

private struct DastakMerchantProductPage: View {
    @ObservedObject var model: DastakMerchantModel
    let selectedID: UUID
    let select: (UUID) -> Void
    let close: () -> Void
    @State private var stock: String
    @State private var stockVersion: Int
    @State private var saved = false
    @State private var addingEmptySKU = false
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ProductDetailPalette { .init(dark: colorScheme == .dark) }

    init(model: DastakMerchantModel, initial: DastakV1MerchantCatalogueSnapshot.SKU, select: @escaping (UUID) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.selectedID = initial.id
        self.select = select
        self.close = close
        _stock = State(initialValue: initial.stockQuantity.map(String.init) ?? "")
        _stockVersion = State(initialValue: initial.selectionVersion)
    }

    var body: some View {
        if let snapshot = model.canonicalCatalogue, let sku = snapshot.skus.first(where: { $0.id == selectedID }) {
            let draft = DastakProductStockDraft(text: stock, currentQuantity: sku.stockQuantity,
                reserved: sku.stockReservedQuantity ?? 0, selected: sku.selected, addingEmptySKU: addingEmptySKU,
                stale: stockVersion != sku.selectionVersion, busy: model.isBusy, active: sku.catalogueStatus == "ACTIVE")
            DastakProductDetailCard(product: DastakDetailProduct(sku),
                products: snapshot.skus.filter { $0.categoryID == sku.categoryID }.map(DastakDetailProduct.init),
                select: select, close: { if !model.isBusy { close() } }
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Available stock").font(.headline)
                        Spacer()
                        Text(sku.selected ? "In your store" : "Not available")
                            .font(.caption2.weight(.semibold)).foregroundStyle(palette.accent)
                    }
                    Text("\(snapshot.branch.branchName) · units of \(sku.packSize)").font(.caption).foregroundStyle(palette.secondary)
                    HStack {
                        Label(sku.stockQuantity.map { "\($0) available" } ?? "Count not set", systemImage: "shippingbox")
                        Spacer()
                        Text("\(sku.stockReservedQuantity ?? 0) reserved")
                    }.font(.caption).foregroundStyle(palette.secondary)
                    HStack {
                        MarketplaceFeedbackButton { stock = String(max(min(max(Int(stock) ?? 0, 0), 1_000_000) - 1, 0)); saved = false } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("Decrease stock count")
                        TextField("Not set", text: $stock).multilineTextAlignment(.center).textFieldStyle(.plain)
                            .font(.title3.weight(.semibold)).foregroundStyle(palette.ink)
                            .padding(.vertical, 12)
                            .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12))
#if os(iOS)
                            .keyboardType(.numberPad)
#endif
                            .accessibilityLabel("Stock quantity")
                            .onChange(of: stock) { _, newValue in
                                if newValue != sku.stockQuantity.map(String.init) { saved = false }
                            }
                        MarketplaceFeedbackButton { stock = String(min(min(max(Int(stock) ?? 0, 0), 1_000_000) + 1, 1_000_000)); saved = false } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Increase stock count")
                    }.buttonStyle(.plain).foregroundStyle(palette.accent).disabled(!draft.canEdit)
                        .opacity(draft.canEdit ? 1 : 0.5)
                    if !draft.isStockMode {
                        Label("Add this product to your store to manage stock.", systemImage: "lock")
                            .font(.caption).foregroundStyle(palette.secondary)
                    } else if addingEmptySKU {
                        Text("Enter a positive stock count to finish adding this product.").font(.caption).foregroundStyle(palette.accent)
                    } else {
                        Text("Orders update stock automatically. Change this count only for restocking or corrections.")
                            .font(.caption).foregroundStyle(palette.secondary)
                    }
                    Text("Enter available, unreserved units. Saving zero makes this product unavailable.")
                        .font(.caption2).foregroundStyle(palette.secondary)
                    if stockVersion != sku.selectionVersion {
                        Text("The stock count has changed.").font(.caption)
                        MarketplaceFeedbackButton("Use latest stock count") {
                            stock = sku.stockQuantity.map(String.init) ?? ""
                            stockVersion = sku.selectionVersion
                            saved = false; addingEmptySKU = false
                        }.disabled(model.isBusy)
                    }
                    if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    if saved { Label("Stock count saved", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                }.productInfoSurface()
            } action: {
                MarketplaceFeedbackButton {
                    guard draft.canSubmit else { return }
                    if !draft.isStockMode && sku.stockQuantity == 0 {
                        addingEmptySKU = true
                        return
                    }
                    Task {
                        let success: Bool
                        if draft.isStockMode, let quantity = draft.quantity {
                            success = await model.saveStockCount(sku, quantity: quantity)
                        } else {
                            success = await model.addCanonicalSKU(sku)
                        }
                        if success, let latest = model.canonicalCatalogue?.skus.first(where: { $0.id == selectedID }) {
                            stock = latest.stockQuantity.map(String.init) ?? ""
                            stockVersion = latest.selectionVersion
                            saved = draft.isStockMode
                            addingEmptySKU = false
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if model.isBusy { ProgressView().tint(.white) }
                        Text(draft.actionTitle).font(.headline.bold())
                    }
                }
                .buttonStyle(ProductStockButtonStyle())
                .disabled(!draft.canSubmit)
            }
        }
    }
}
