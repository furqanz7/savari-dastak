import ImageIO
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI

struct DastakMerchantRestaurantMenuView: View {
    @ObservedObject var model: DastakMerchantModel
    @State private var categoryName = ""
    @State private var itemName = ""
    @State private var itemPrice = ""
    @State private var itemCategoryID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let menu = model.restaurantMenu {
                    LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR KITCHEN").font(.caption2.bold()).tracking(1.2).foregroundStyle(MarketplaceColors.dastakAccent.color)
                            Text(menu.restaurant.name).font(MarketplaceTypography.instrumentSerif(fixedSize: 38))
                            Text("Your menu, made easy to manage.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        restaurantBanner(menu)
                        addMenuContent(menu)
                        if menu.categories.isEmpty {
                            DastakEmptyState(symbol: "fork.knife", title: "Make this menu yours", message: "Add your first category and dish above.")
                                .frame(minHeight: 260)
                        } else {
                            ForEach(menu.categories) { category in
                                categorySection(category)
                            }
                        }
                    }
                    .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .padding(.bottom, 140)
                    .frame(maxWidth: .infinity)
                }
            }
            .refreshable { await model.refreshRestaurantMenu() }
            .navigationTitle("Restaurant menu")
            .dastakInlineNavigationTitle()
        }
    }

    private func restaurantBanner(_ menu: DastakV1RestaurantMenu) -> some View {
        DastakMerchantMediaPicker(
            title: "Restaurant banner",
            message: "Shown at the top of your restaurant and menu. Use a clear landscape photo without text.",
            imageKey: menu.restaurant.imageKey,
            busy: model.isBusy
        ) { media in
            await model.uploadRestaurantMedia(
                entityType: "RESTAURANT_BRANCH_BANNER", entityID: menu.restaurant.branchID,
                expectedMediaVersion: menu.restaurant.mediaVersion ?? 1,
                data: media.data, contentType: media.contentType, fileName: media.fileName
            )
        }
    }

    private func addMenuContent(_ menu: DastakV1RestaurantMenu) -> some View {
        DisclosureGroup("Add to your menu") {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New category").font(.headline)
                    TextField("Breakfast", text: $categoryName).textFieldStyle(.roundedBorder)
                    Button("Add category", systemImage: "plus") {
                        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: .category(name: name, description: "", sortOrder: menu.categories.count, status: "ACTIVE")) { categoryName = "" }
                        }
                    }
                    .buttonStyle(MarketplaceSecondaryButtonStyle()).disabled(model.isBusy || categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("New dish").font(.headline)
                    Picker("Category", selection: $itemCategoryID) {
                        Text("Choose category").tag(UUID?.none)
                        ForEach(menu.categories) { Text($0.name).tag(UUID?.some($0.id)) }
                    }.pickerStyle(.menu)
                    TextField("Dish name", text: $itemName).textFieldStyle(.roundedBorder)
                    TextField("Price in rupees", text: $itemPrice).dastakDecimalKeyboard().textFieldStyle(.roundedBorder)
                    Button("Add dish", systemImage: "plus") {
                        guard let categoryID = itemCategoryID, let paise = DastakMerchantPriceParser.optionalPaise(from: itemPrice) else { return }
                        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: .item(categoryID: categoryID, name: name, description: "", imageKey: "", basePricePaise: paise, taxRateBps: 0, logisticsAttributes: DastakV1SKULogistics(), status: "ACTIVE")) { itemName = ""; itemPrice = "" }
                        }
                    }
                    .buttonStyle(MarketplacePrimaryButtonStyle()).disabled(model.isBusy || itemCategoryID == nil || itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(.top, MarketplaceSpacing.medium)
        }
        .padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
    }

    private func categorySection(_ category: DastakV1RestaurantMenuCategory) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.name).font(.title3.bold())
                    Text("\(category.items.count) items · \(category.status.lowercased())").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(category.status == "ACTIVE" ? "Hide" : "Activate") {
                    Task { _ = await model.saveRestaurantEntity(entityID: category.id, expectedVersion: category.version, payload: .category(name: category.name, description: category.description ?? "", sortOrder: category.sortOrder, status: category.status == "ACTIVE" ? "INACTIVE" : "ACTIVE")) }
                }.buttonStyle(MarketplaceSecondaryButtonStyle()).disabled(model.isBusy)
            }
            ForEach(category.items) { item in
                DastakMerchantDishEditor(model: model, categoryID: category.id, item: item)
            }
        }.padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
    }
}

private struct DastakMerchantDishEditor: View {
    @ObservedObject var model: DastakMerchantModel
    let categoryID: UUID
    let item: DastakV1RestaurantMenuItem
    @State private var name: String
    @State private var description: String
    @State private var price: String
    @State private var groupName = ""
    @State private var selectionType = "SINGLE"

    init(model: DastakMerchantModel, categoryID: UUID, item: DastakV1RestaurantMenuItem) {
        self.model = model; self.categoryID = categoryID; self.item = item
        _name = State(initialValue: item.name); _description = State(initialValue: item.description ?? "")
        _price = State(initialValue: String(format: "%.2f", Double(item.basePricePaise) / 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakMerchantMediaPicker(title: "Dish photo", message: "Optional. A clear photo helps customers recognise this dish.", imageKey: item.imageKey, compact: true, busy: model.isBusy) { media in
                await model.uploadRestaurantMedia(entityType: "RESTAURANT_MENU_ITEM", entityID: item.id, expectedMediaVersion: item.mediaVersion ?? 1, data: media.data, contentType: media.contentType, fileName: media.fileName)
            }
            TextField("Dish name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Description", text: $description).textFieldStyle(.roundedBorder)
            TextField("Price in rupees", text: $price).dastakDecimalKeyboard().textFieldStyle(.roundedBorder)
            HStack {
                Button("Save changes") { save() }.buttonStyle(MarketplacePrimaryButtonStyle()).disabled(model.isBusy)
                Button(item.status == "ACTIVE" ? "Mark unavailable" : "Activate") { save(status: item.status == "ACTIVE" ? "INACTIVE" : "ACTIVE") }.buttonStyle(MarketplaceSecondaryButtonStyle()).disabled(model.isBusy)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                    ForEach(item.optionGroups) { group in
                        DastakMerchantChoiceGroup(model: model, itemID: item.id, group: group)
                    }
                    Text("Example: “Choose a size” with Small, Medium and Large; or “Add extras” with Cheese and Sauce.").font(.caption).foregroundStyle(.secondary)
                    TextField("Choice name, e.g. Choose a size", text: $groupName).textFieldStyle(.roundedBorder)
                    Picker("How customers choose", selection: $selectionType) { Text("One option").tag("SINGLE"); Text("One or more options").tag("MULTIPLE") }.pickerStyle(.segmented)
                    Button("Add choice group", systemImage: "plus") {
                        let value = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { if await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: .optionGroup(menuItemID: item.id, name: value, selectionType: selectionType, minimumSelections: 0, maximumSelections: selectionType == "SINGLE" ? 1 : 20, sortOrder: item.optionGroups.count, status: "ACTIVE")) { groupName = "" } }
                    }.buttonStyle(MarketplaceSecondaryButtonStyle()).disabled(model.isBusy || groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.top, 10)
            } label: {
                VStack(alignment: .leading, spacing: 2) { Text("Customer choices & extras").font(.headline); Text("Sizes, flavours, preparation choices or paid extras").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, MarketplaceSpacing.small)
    }

    private func save(status: String? = nil) {
        guard let paise = DastakMerchantPriceParser.optionalPaise(from: price) else { return }
        Task { _ = await model.saveRestaurantEntity(entityID: item.id, expectedVersion: item.version, payload: .item(categoryID: categoryID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description.trimmingCharacters(in: .whitespacesAndNewlines), imageKey: item.imageKey ?? "", basePricePaise: paise, taxRateBps: item.taxRateBps, logisticsAttributes: item.logisticsAttributes, status: status ?? item.status)) }
    }
}

private struct DastakMerchantChoiceGroup: View {
    @ObservedObject var model: DastakMerchantModel
    let itemID: UUID
    let group: DastakV1RestaurantMenuOptionGroup
    @State private var optionName = ""
    @State private var optionPrice = "0"

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { VStack(alignment: .leading) { Text(group.name).bold(); Text(group.selectionType == "SINGLE" ? "Customer chooses one option" : "Customer may choose more than one").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(group.status == "ACTIVE" ? "Hide" : "Activate") { Task { _ = await model.saveRestaurantEntity(entityID: group.id, expectedVersion: group.version, payload: .optionGroup(menuItemID: itemID, name: group.name, selectionType: group.selectionType, minimumSelections: group.minimumSelections, maximumSelections: group.maximumSelections, sortOrder: group.sortOrder, status: group.status == "ACTIVE" ? "INACTIVE" : "ACTIVE")) } }.font(.caption.bold()) }
            ForEach(group.options) { option in HStack { Text(option.name); Spacer(); Text(DastakFormatting.money(Money(paise: option.priceDeltaPaise))); Text(option.status.lowercased()).font(.caption).foregroundStyle(.secondary) } }
            HStack { TextField("Option name", text: $optionName).textFieldStyle(.roundedBorder); TextField("Extra ₹", text: $optionPrice).dastakDecimalKeyboard().frame(width: 92).textFieldStyle(.roundedBorder) }
            Button("Add option", systemImage: "plus") {
                guard let paise = DastakMerchantPriceParser.optionalNonnegativePaise(from: optionPrice) else { return }
                let value = optionName.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { if await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: .option(optionGroupID: group.id, name: value, priceDeltaPaise: paise, sortOrder: group.options.count, status: "ACTIVE")) { optionName = ""; optionPrice = "0" } }
            }.buttonStyle(MarketplaceSecondaryButtonStyle()).disabled(model.isBusy || optionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(12).background(MarketplaceColors.dastakAccentSoft.color.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DastakMerchantImageUpload: Sendable { let data: Data; let contentType: String; let fileName: String }

private struct DastakMerchantMediaPicker: View {
    let title: String
    let message: String
    let imageKey: String?
    var compact = false
    let busy: Bool
    let upload: (DastakMerchantImageUpload) async -> Bool
    @State private var selection: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        let actionTitle = loading ? "Uploading…" : imageKey == nil ? "Add photo" : "Replace"
        HStack(spacing: 14) {
            DastakProductArtwork(imageKey: imageKey, fallbackSymbol: "camera")
                .frame(width: compact ? 76 : 108, height: compact ? 66 : 76)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(message).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            PhotosPicker(selection: $selection, matching: .images) { Label(actionTitle, systemImage: "photo.badge.plus") }.buttonStyle(MarketplaceSecondaryButtonStyle()).disabled(busy || loading)
        }
        .padding(compact ? 12 : 16).marketplaceFlatSurface()
        .onChange(of: selection) { _, item in
            guard let item else { return }
            loading = true
            Task {
                defer { loading = false; selection = nil }
                guard let data = try? await item.loadTransferable(type: Data.self), let inspected = DastakMerchantImageInspector.inspect(data) else { return }
                _ = await upload(.init(data: data, contentType: inspected.contentType, fileName: "restaurant-\(UUID().uuidString.lowercased()).\(inspected.extension)"))
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func dastakDecimalKeyboard() -> some View {
#if canImport(UIKit)
        keyboardType(.decimalPad)
#else
        self
#endif
    }
}

enum DastakMerchantImageInspector {
    static func inspect(_ data: Data) -> (contentType: String, extension: String)? {
        guard !data.isEmpty, data.count <= 5 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0,
              (properties[kCGImagePropertyPixelHeight] as? Int ?? 0) > 0
        else { return nil }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return ("image/jpeg", "jpg") }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("image/png", "png") }
        if bytes.count >= 12, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF", String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" { return ("image/webp", "webp") }
        return nil
    }
}

extension DastakMerchantPriceParser {
    static func optionalPaise(from value: String) -> Int? { try? paise(from: value) }
    static func optionalNonnegativePaise(from value: String) -> Int? {
        guard let decimal = Decimal(string: value.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX")), decimal >= 0, decimal <= 1_000_000 else { return nil }
        var scaled = decimal * 100; var rounded = Decimal(); NSDecimalRound(&rounded, &scaled, 0, .plain)
        return rounded == scaled ? NSDecimalNumber(decimal: rounded).intValue : nil
    }
}
