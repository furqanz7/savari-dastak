import ImageIO
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import PhotosUI
import SwiftUI

struct DastakMerchantRestaurantMenuView: View {
    @ObservedObject var model: DastakMerchantModel
    @ObservedObject private var drafts: DastakMerchantMenuDraftStore
    let branchID: UUID?
    private var categoryName: String { drafts.composer.categoryName }
    private var itemName: String { drafts.composer.itemName }
    private var itemPrice: String { drafts.composer.itemPrice }
    private var itemCategoryID: UUID? { drafts.composer.itemCategoryID }
    @State private var discardingDrafts = false
    @State private var operatingAction: OperatingAction?
    @State private var query = ""

    init(model: DastakMerchantModel) {
        self.model = model
        self.drafts = model.menuDrafts
        self.branchID = model.restaurantMenu?.restaurant.branchID
    }

    private enum OperatingAction: String, Identifiable {
        case open = "Open restaurant", close = "Close restaurant", pause = "Pause new orders", resume = "Accept new orders"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let menu = model.restaurantMenu, menu.restaurant.branchID == branchID {
                    LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                        DastakMerchantLocationView(model: model, presentation: .menu)
                        restaurantStatus(menu)
                        if let reason = model.restaurantEditUnavailableReason {
                            Text(reason).font(.footnote).foregroundStyle(.secondary)
                        }
                        operatingControls(menu)
                        restaurantBanner(menu)
                        menuSearch(menu)
                        draftStorageStatus(menu)
                        unavailableDrafts
                        addMenuContent(menu)
                            .disabled(model.restaurantChangesDisabled)
                        if menu.categories.isEmpty {
                            DastakEmptyState(symbol: "fork.knife", title: "Make this menu yours", message: "Add your first category and dish above.")
                                .frame(minHeight: 260)
                        } else {
                            ForEach(DastakMerchantMenuSearch.categories(menu.categories, query: query)) { category in
                                categorySection(category)
                                    .disabled(model.restaurantChangesDisabled)
                            }
                            if DastakMerchantMenuSearch.categories(menu.categories, query: query).isEmpty {
                                DastakEmptyState(symbol: "magnifyingglass", title: "No matching menu entries", message: "Try a category, dish, description or extra name. Hidden entries are included in search.")
                            }
                        }
                    }
                    .frame(maxWidth: MarketplaceMetrics.contentMaxWidth)
                    .padding(.horizontal, MarketplaceSpacing.medium)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
            }
            .refreshable { await model.refreshRestaurantMenu() }
            .navigationTitle("Restaurant menu")
            .dastakInlineNavigationTitle()
            .modifier(DastakMerchantKeyboardDismiss())
            .onChange(of: model.restaurantMenu?.restaurant.operationalVersion) { _, _ in operatingAction = nil }
            .onChange(of: model.restaurantMenu?.restaurant.branchID) { _, _ in operatingAction = nil }
            .onChange(of: model.restaurantMenu?.restaurant.branchStatus) { _, _ in operatingAction = nil }
            .confirmationDialog(operatingAction?.rawValue ?? "Restaurant operating state",
                isPresented: Binding(get: { operatingAction != nil }, set: { if !$0 { operatingAction = nil } }),
                titleVisibility: .visible) {
                if let action = operatingAction {
                    Button(action.rawValue, role: action == .close ? .destructive : nil) {
                        operatingAction = nil
                        Task {
                            await model.setRestaurantOperatingState(isOpen: action != .close,
                                acceptingOrders: action == .resume, branchID: branchID)
                        }
                    }
                    .disabled(!model.canChangeRestaurantOperatingState)
                }
                Button("Cancel", role: .cancel) { operatingAction = nil }
            } message: {
                Text("Existing confirmed orders continue. Opening keeps new orders paused until you choose Accept new orders.")
            }
        }
    }

    private func menuSearch(_ menu: DastakV1RestaurantMenu) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search categories, dishes or extras", text: $query)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("merchant.menu.search")
                if !query.isEmpty { Button("Clear", systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }
            }
            Text("\(DastakMerchantMenuSearch.categories(menu.categories, query: query).reduce(0) { $0 + DastakMerchantMenuSearch.items($1, query: query).count }) matching dishes · includes hidden entries")
                .font(.caption).foregroundStyle(.secondary)
            if drafts.dirtyCount > 0 { Text("\(drafts.dirtyCount) unsaved or review-needed drafts, including entries hidden by search. These do not change your live menu until you save.").font(.caption).foregroundStyle(.secondary) }
        }.padding(16).marketplaceFlatSurface()
    }

    private func draftStorageStatus(_ menu: DastakV1RestaurantMenu) -> some View {
        VStack(alignment: .leading,spacing: 10) {
            if let failure = drafts.persistenceFailure {
                Label(failure,systemImage: "externaldrive.badge.exclamationmark").font(.footnote)
                if drafts.needsRestoreRetry {
                    Button("Retry reading saved drafts") { drafts.retryRestoring(menu) }.frame(minHeight: 44)
                        .disabled(drafts.dirtyCount>0 || model.needsRestaurantRefresh || model.isRefreshingRestaurant)
                    if drafts.dirtyCount>0 { Text("Copy your new edits before discarding local drafts; retrying a stored file will not replace new typing automatically.").font(.caption).foregroundStyle(.secondary) }
                } else { Button("Retry draft storage") { drafts.retryPersistence() }.frame(minHeight: 44) }
            } else if drafts.usesDeviceStorage {
                Text("Drafts stay privately on this device for this account and store. After reopening, fresh menu details are checked before edits can be saved.").font(.caption).foregroundStyle(.secondary)
            }
            if drafts.dirtyCount>0 || drafts.persistenceFailure != nil {
                Button("Discard local drafts for this store",role: .destructive) { discardingDrafts = true }
                    .frame(minHeight: 44).disabled(model.busyIdentity != nil || model.isRefreshingRestaurant)
            }
        }.confirmationDialog("Discard local menu drafts?",isPresented: $discardingDrafts,titleVisibility: .visible) {
            Button("Discard this store's local drafts",role: .destructive) { drafts.discardLocalDrafts(menu) }.disabled(model.busyIdentity != nil || model.isRefreshingRestaurant)
            Button("Keep drafts",role: .cancel) {}
        } message: { Text("This removes unsaved edits on this device for this account and store only. It does not change your live menu, other stores, or the saved-action recovery journal.") }
    }

    @ViewBuilder private var unavailableDrafts: some View {
        if !drafts.unavailable.isEmpty || !drafts.unavailableAdditions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Entries no longer in this menu", systemImage: "exclamationmark.triangle").font(.headline)
                Text("These drafts are retained for reference, but cannot be saved. Refresh or copy the text before discarding.").font(.caption).foregroundStyle(.secondary)
                ForEach(drafts.unavailable, id: \.baseline.id) { draft in
                    Text("\(draft.value.name)\(draft.value.price.isEmpty ? "" : " · ₹" + draft.value.price)\n\(draft.value.description)").textSelection(.enabled)
                    Button("Discard unavailable draft", role: .destructive) { drafts.discardUnavailable(draft.baseline.id) }
                }
                ForEach(drafts.unavailableAdditions, id: \.0) { id, value in
                    Text("New choice/extra · \(value.name) · ₹\(value.price)").textSelection(.enabled)
                    Button("Discard unavailable new-entry draft", role: .destructive) { drafts.discardUnavailable(id) }
                }
            }.padding(16).marketplaceFlatSurface()
        }
    }

    private func restaurantStatus(_ menu: DastakV1RestaurantMenu) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            if let notice = model.notice { Text(notice).font(.subheadline).accessibilityIdentifier("merchant.restaurant.notice") }
            if let pending = model.pendingRestaurantCommand {
                Label("Pending: \(pending.description)", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Text("The result is uncertain. Other restaurant changes are paused. Retry checks this same action and original details; do not submit it again as a new change.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Check pending restaurant change") { Task { await model.retryRestaurantCommand() } }
                    .buttonStyle(DastakMerchantActionStyle()).disabled(model.busyIdentity != nil || !model.merchantJournalRestored)
                    .accessibilityIdentifier("merchant.restaurant.retryPending")
            }
            if let failure = model.restaurantRefreshFailure {
                Text(failure).font(.subheadline).foregroundStyle(.secondary)
            }
            if model.isRefreshingRestaurant {
                ProgressView("Refreshing restaurant details")
            } else if model.needsRestaurantRefresh {
                Button("Refresh restaurant details") { Task { await model.refreshRestaurantMenu(reportFailure: false) } }
                    .buttonStyle(DastakMerchantActionStyle()).disabled(model.isBusy || model.isRefreshingRestaurant)
            }
            if menu.restaurant.operationalVersion == nil {
                Text("Operating controls are unavailable until Dastak provides the current restaurant version. Refresh or contact support.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("merchant.restaurant.status")
    }

    private func operatingControls(_ menu: DastakV1RestaurantMenu) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Label(menu.restaurant.isOpen ? "Restaurant open" : "Restaurant closed", systemImage: "storefront")
                Button(menu.restaurant.isOpen ? "Close" : "Open") {
                    operatingAction = menu.restaurant.isOpen ? .close : .open
                }
                .disabled(!model.canChangeRestaurantOperatingState)
                .accessibilityIdentifier("merchant.restaurant.open")
            }
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Label(menu.restaurant.acceptingOrders ? "Accepting food orders" : "New food orders paused", systemImage: "pause.circle")
                Button(menu.restaurant.acceptingOrders ? "Pause" : "Accept new orders") {
                    operatingAction = menu.restaurant.acceptingOrders ? .pause : .resume
                }
                .disabled(!model.canChangeRestaurantOperatingState)
                .accessibilityIdentifier("merchant.restaurant.accepting")
            }
            Text("\(menu.restaurant.activeOrderCount) active orders · Changes apply to new requests, not confirmed orders.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .buttonStyle(DastakMerchantActionStyle())
        .padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
    }

    private func restaurantBanner(_ menu: DastakV1RestaurantMenu) -> some View {
        DastakMerchantMediaPicker(
            title: "Restaurant banner",
            message: "Shown at the top of your restaurant and menu. Use a clear landscape photo without text.",
            imageKey: menu.restaurant.imageKey,
            busy: model.restaurantChangesDisabled
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
                    TextField("Breakfast", text: composerField(\.categoryName)).textFieldStyle(.roundedBorder)
                    if !categoryName.isEmpty, let issue = DastakMerchantValidation.nameIssue(categoryName, maximum: 100, field: "a category name") {
                        Text(issue).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Add category", systemImage: "plus") {
                        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            _ = await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: .category(name: name, description: "", sortOrder: menu.categories.count, status: "ACTIVE"), branchID: branchID)
                        }
                    }
                    .buttonStyle(DastakMerchantActionStyle()).disabled(model.isBusy || !(1...100).contains(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count))
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("New dish").font(.headline)
                    Picker("Category", selection: Binding(get: { itemCategoryID },set: { var value = drafts.composer; value.itemCategoryID = $0; drafts.editComposer(value) })) {
                        Text("Choose category").tag(UUID?.none)
                        ForEach(menu.categories) { Text($0.name).tag(UUID?.some($0.id)) }
                    }.pickerStyle(.menu)
                    TextField("Dish name", text: composerField(\.itemName)).textFieldStyle(.roundedBorder)
                    if !itemName.isEmpty, let issue = DastakMerchantValidation.nameIssue(itemName, maximum: 160, field: "a dish name") {
                        Text(issue).font(.caption).foregroundStyle(.secondary)
                    }
                    if itemCategoryID == nil { Text("Choose a category before adding a dish.").font(.caption).foregroundStyle(.secondary) }
                    if let itemCategoryID, !menu.categories.contains(where: { $0.id == itemCategoryID }) {
                        Text("The draft's category is no longer available. Choose a current category before adding this dish.").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Price in rupees", text: composerField(\.itemPrice)).dastakDecimalKeyboard().textFieldStyle(.roundedBorder)
                    Button("Add dish", systemImage: "plus") {
                        guard let categoryID = itemCategoryID, let paise = DastakMerchantPriceParser.optionalPaise(from: itemPrice) else {
                            model.errorMessage = "Choose a category. " + DastakMerchantValidation.priceHelp; return
                        }
                        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            _ = await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0, payload: .item(categoryID: categoryID, name: name, description: "", imageKey: "", basePricePaise: paise, taxRateBps: 0, logisticsAttributes: DastakV1SKULogistics(), status: "ACTIVE"), branchID: branchID)
                        }
                    }
                    .buttonStyle(DastakMerchantActionStyle(primary: true)).disabled(model.isBusy || !menu.categories.contains { $0.id == itemCategoryID } || !(1...160).contains(itemName.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count) || DastakMerchantPriceParser.optionalPaise(from: itemPrice) == nil)
                    Text(DastakMerchantValidation.priceHelp).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, MarketplaceSpacing.medium)
        }
        .padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
    }

    private func categorySection(_ category: DastakV1RestaurantMenuCategory) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            DastakMerchantAdaptiveRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.name).font(.title3.bold())
                    Text("\(category.items.count) items · \(category.status.lowercased())").font(.caption).foregroundStyle(.secondary)
                }
            }
            DastakMerchantMenuCategoryEditor(model: model,drafts: drafts,category: category,branchID: branchID)
            ForEach(DastakMerchantMenuSearch.items(category, query: query)) { item in
                DastakMerchantMenuDishEditor(model: model, drafts: drafts, item: item, branchID: branchID)
            }
        }.padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
    }

    private func composerField(_ path: WritableKeyPath<DastakMerchantMenuComposer,String>) -> Binding<String> {
        Binding(get: { drafts.composer[keyPath: path] },set: { var value = drafts.composer; value[keyPath: path] = $0; drafts.editComposer(value) })
    }
}

struct DastakMerchantImageUpload: Sendable { let data: Data; let contentType: String; let fileName: String }

struct DastakMerchantMediaPicker: View {
    let title: String
    let message: String
    let imageKey: String?
    var compact = false
    let busy: Bool
    let upload: (DastakMerchantImageUpload) async -> Bool
    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var photoMessage: String?
    @State private var generation = UUID()

    var body: some View {
        let actionTitle = loading ? "Processing photo…" : imageKey == nil ? "Add photo" : "Replace"
        VStack(alignment: .leading, spacing: 10) {
          if !compact {
            DastakRestaurantBanner(imageKey: imageKey)
                .frame(maxWidth: .infinity).frame(height: 160).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Current restaurant banner")
          }
          DastakMerchantAdaptiveRow {
            if compact { DastakProductArtwork(imageKey: imageKey, fallbackSymbol: "camera").frame(width: 72, height: 72).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(message).font(.caption).foregroundStyle(.secondary) }
          }
          PhotosPicker(selection: $selection, matching: .images) { Label(actionTitle, systemImage: "photo.badge.plus") }
              .buttonStyle(DastakMerchantActionStyle()).disabled(busy || loading)
          Text("JPEG, PNG or WebP up to 5 MB. HEIC up to 20 MB is converted to JPEG on this device.")
              .font(.caption).foregroundStyle(.secondary)
          if let photoMessage { Text(photoMessage).font(.caption).accessibilityIdentifier("merchant.photo.feedback") }
        }
        .padding(compact ? 12 : 16).marketplaceFlatSurface()
        .onChange(of: selection) { _, item in
            guard let item else { return }
            let token = UUID(); generation = token; loading = true; photoMessage = nil
            Task {
                defer { if generation == token { loading = false; selection = nil } }
                do {
                    let photo = try await DastakMerchantPhoto.load(purpose: .catalogue) { try await item.loadTransferable(type: Data.self) }
                    guard generation == token, !Task.isCancelled else { return }
                    guard !busy else { photoMessage = "The Store changed while this photo was loading. Review the latest details and choose it again."; return }
                    let saved = await upload(.init(data: photo.data, contentType: photo.contentType,
                        fileName: "restaurant-\(UUID().uuidString.lowercased()).\(photo.fileExtension)"))
                    guard generation == token else { return }
                    photoMessage = saved ? (photo.converted ? "HEIC converted to JPEG. Photo saved." : "Photo saved.")
                        : "Photo not confirmed. Check the Store message or saved-action recovery above before trying again."
                } catch { if generation == token { photoMessage = DastakMerchantPhoto.failureMessage(error) } }
            }
        }
        .onDisappear { generation = UUID(); loading = false; selection = nil }
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
        guard let photo = try? DastakMerchantPhoto.prepare(data, purpose: .catalogue), !photo.converted else { return nil }
        return (photo.contentType, photo.fileExtension)
    }
}

extension DastakMerchantPriceParser {
    static func optionalPaise(from value: String) -> Int? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[0-9]{1,7}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil else { return nil }
        return try? paise(from: value)
    }
    static func optionalNonnegativePaise(from value: String) -> Int? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[0-9]{1,7}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), decimal >= 0, decimal <= 1_000_000 else { return nil }
        var scaled = decimal * 100; var rounded = Decimal(); NSDecimalRound(&rounded, &scaled, 0, .plain)
        return rounded == scaled ? NSDecimalNumber(decimal: rounded).intValue : nil
    }
}
