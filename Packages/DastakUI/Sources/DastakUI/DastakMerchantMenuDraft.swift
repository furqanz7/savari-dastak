import Foundation
import MarketplaceInfrastructure

struct DastakMerchantMenuSource: Codable, Equatable {
    let id: UUID
    let version: Int
    let mediaVersion: Int
    let payload: DastakV1RestaurantMenuPayload
    var status: String {
        switch payload {
        case let .item(_, _, _, _, _, _, _, status), let .option(_, _, _, _, status): status
        case let .category(_, _, _, status), let .optionGroup(_, _, _, _, _, _, status): status
        }
    }
    var fields: DastakMerchantMenuFields {
        switch payload {
        case let .item(_, name, description, _, price, _, _, _): .init(name: name, description: description, price: Self.price(price))
        case let .option(_, name, price, _, _): .init(name: name, description: "", price: Self.price(price))
        case let .category(name, description, order, _): .init(name: name, description: description, price: "", order: String(order))
        case let .optionGroup(_, name, type, minimum, maximum, order, _):
            .init(name: name, description: "", price: "", order: String(order), selectionType: type, minimum: String(minimum), maximum: String(maximum))
        }
    }
    static func price(_ paise: Int) -> String { NSDecimalNumber(decimal: Decimal(paise) / 100).stringValue }
    static func item(_ item: DastakV1RestaurantMenuItem, categoryID: UUID) -> Self {
        .init(id: item.id, version: item.version, mediaVersion: item.mediaVersion ?? 1,
              payload: .item(categoryID: categoryID, name: item.name, description: item.description ?? "", imageKey: item.imageKey ?? "",
                             basePricePaise: item.basePricePaise, taxRateBps: item.taxRateBps, logisticsAttributes: item.logisticsAttributes, status: item.status))
    }
    static func option(_ option: DastakV1RestaurantMenuOption, groupID: UUID) -> Self {
        .init(id: option.id, version: option.version, mediaVersion: 0,
              payload: .option(optionGroupID: groupID, name: option.name, priceDeltaPaise: option.priceDeltaPaise, sortOrder: option.sortOrder, status: option.status))
    }
    static func category(_ category: DastakV1RestaurantMenuCategory) -> Self {
        .init(id: category.id, version: category.version, mediaVersion: 0,
              payload: .category(name: category.name, description: category.description ?? "", sortOrder: category.sortOrder, status: category.status))
    }
    static func group(_ group: DastakV1RestaurantMenuOptionGroup, itemID: UUID) -> Self {
        .init(id: group.id, version: group.version, mediaVersion: 0,
              payload: .optionGroup(menuItemID: itemID, name: group.name, selectionType: group.selectionType,
                minimumSelections: group.minimumSelections, maximumSelections: group.maximumSelections, sortOrder: group.sortOrder, status: group.status))
    }
}
struct DastakMerchantMenuFields: Codable, Equatable {
    var name: String; var description: String; var price: String
    var order = "0"
    var selectionType = "SINGLE"
    var minimum = "0"
    var maximum = "1"
    var sortOrder: Int? {
        guard order.range(of: "^-?[0-9]{1,10}$", options: .regularExpression) != nil,
              let value = Int(order), (Int(Int32.min)...Int(Int32.max)).contains(value) else { return nil }
        return value
    }
    var choiceLimits: (Int,Int)? {
        guard ["SINGLE","MULTIPLE"].contains(selectionType),
              minimum.range(of: "^[0-9]{1,10}$", options: .regularExpression) != nil,
              maximum.range(of: "^[0-9]{1,10}$", options: .regularExpression) != nil,
              let min = Int(minimum), let max = Int(maximum), min>=0, max>=1, min<=max,
              max<=Int(Int32.max), selectionType != "SINGLE" || max==1 else { return nil }
        return (min,max)
    }
}
struct DastakMerchantMenuEdit: Equatable {
    let branchID: UUID
    let entityID: UUID
    let expectedVersion: Int
    let payload: DastakV1RestaurantMenuPayload
}
struct DastakMerchantMenuDraft: Codable, Equatable {
    var value: DastakMerchantMenuFields
    private(set) var baseline: DastakMerchantMenuSource
    private(set) var latest: DastakMerchantMenuSource?
    private(set) var stale = false
    init(_ source: DastakMerchantMenuSource) { baseline = source; latest = source; value = source.fields }
    var dirty: Bool { value != baseline.fields }
    var canSave: Bool { latest != nil && !stale && validation == nil }
    var validation: String? {
        let trimmed = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = baseline.payload.entityType == "ITEM" ? 160 : 100
        guard (1...limit).contains(trimmed.unicodeScalars.count) else { return "Enter a name from 1 to \(limit) characters." }
        let descriptionLimit = baseline.payload.entityType == "CATEGORY" ? 500 : 1_000
        guard value.description.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count <= descriptionLimit else { return "Keep the description within \(descriptionLimit) characters." }
        if ["CATEGORY","OPTION_GROUP"].contains(baseline.payload.entityType), value.sortOrder == nil { return "Enter a supported whole-number display order. Smaller numbers appear first." }
        if baseline.payload.entityType == "CATEGORY" { return nil }
        if baseline.payload.entityType == "OPTION_GROUP" { return value.choiceLimits == nil ? "Enter valid choice limits: minimum 0 or more, maximum at least 1, and minimum no greater than maximum. A single choice has maximum 1." : nil }
        let paise = baseline.payload.entityType == "ITEM" ? DastakMerchantPriceParser.optionalPaise(from: value.price) : DastakMerchantPriceParser.optionalNonnegativePaise(from: value.price)
        return paise == nil ? (baseline.payload.entityType == "ITEM" ? DastakMerchantValidation.priceHelp : DastakMerchantValidation.extraPriceHelp) : nil
    }
    mutating func reconcile(_ source: DastakMerchantMenuSource?) {
        guard let source else { latest = nil; stale = true; return }
        guard source.version >= max(baseline.version, latest?.version ?? 0),
              source.mediaVersion >= max(baseline.mediaVersion, latest?.mediaVersion ?? 0) else { return }
        if source == latest { return }
        if !dirty && !stale { self = .init(source) }
        else { latest = source; stale = true }
    }
    mutating func useLatest() { if let latest { self = .init(latest) } }
    mutating func keepAfterReview() {
        guard let latest else { return }
        baseline = latest; stale = false
    }
    func command(branchID: UUID, status: String? = nil) -> DastakMerchantMenuEdit? {
        guard canSave, status == nil || !dirty else { return nil }
        let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: DastakV1RestaurantMenuPayload
        switch baseline.payload {
        case let .category(_, _, _, previousStatus):
            guard let order = value.sortOrder else { return nil }
            payload = .category(name: name, description: value.description.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: order, status: status ?? previousStatus)
        case let .optionGroup(itemID, _, _, _, _, _, previousStatus):
            guard let order = value.sortOrder, let limits = value.choiceLimits else { return nil }
            payload = .optionGroup(menuItemID: itemID, name: name, selectionType: value.selectionType,
                minimumSelections: limits.0, maximumSelections: limits.1, sortOrder: order, status: status ?? previousStatus)
        case let .item(categoryID, _, _, image, _, tax, logistics, previousStatus):
            guard let paise = DastakMerchantPriceParser.optionalPaise(from: value.price) else { return nil }
            payload = .item(categoryID: categoryID, name: name, description: value.description.trimmingCharacters(in: .whitespacesAndNewlines), imageKey: image,
                            basePricePaise: paise, taxRateBps: tax, logisticsAttributes: logistics, status: status ?? previousStatus)
        case let .option(groupID, _, _, order, previousStatus):
            guard let paise = DastakMerchantPriceParser.optionalNonnegativePaise(from: value.price) else { return nil }
            payload = .option(optionGroupID: groupID, name: name, priceDeltaPaise: paise, sortOrder: order, status: status ?? previousStatus)
        }
        return .init(branchID: branchID, entityID: baseline.id, expectedVersion: baseline.version, payload: payload)
    }
}

struct DastakMerchantMenuAddition: Codable, Equatable {
    var name = ""
    var price = "0"
    var selectionType = "SINGLE"
    var maximum = "2"
    var minimum = "0"
    var dirty: Bool { !name.isEmpty || price != "0" || selectionType != "SINGLE" || maximum != "2" || minimum != "0" }
    var minimumSelections: Int? {
        guard minimum.range(of: "^[0-9]{1,10}$", options: .regularExpression) != nil,
              let value = Int(minimum), let maximumSelections, (0...maximumSelections).contains(value) else { return nil }
        return value
    }
    var maximumSelections: Int? {
        if selectionType == "SINGLE" { return 1 }
        guard selectionType == "MULTIPLE", maximum.range(of: "^[0-9]{1,10}$", options: .regularExpression) != nil,
              let count = Int(maximum), (1...Int(Int32.max)).contains(count) else { return nil }
        return count
    }
    var validName: Bool { (1...100).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count) }
}

struct DastakMerchantMenuComposer: Codable, Equatable {
    var categoryName = ""
    var itemName = ""
    var itemPrice = ""
    var itemCategoryID: UUID?
    var dirty: Bool { !categoryName.isEmpty || !itemName.isEmpty || !itemPrice.isEmpty || itemCategoryID != nil }
}

/// Workspace-owned drafts; only verified actor/location context may restore
/// the optional protected local archive. No draft is automatically submitted.
@MainActor final class DastakMerchantMenuDraftStore: ObservableObject {
    @Published private(set) var branchID: UUID?
    @Published private(set) var records: [UUID: DastakMerchantMenuDraft] = [:]
    @Published private(set) var additions: [UUID: DastakMerchantMenuAddition] = [:]
    @Published private(set) var composer = DastakMerchantMenuComposer()
    @Published private(set) var persistenceFailure: String?
    private var accountID: UUID?
    private var revision: UUID?
    private var lastSaved: DastakMerchantMenuDraftArchive?
    private var restoreBlocked = false
    private let storage: (any DastakMerchantMenuDraftStorage)?
    private var parents: Set<UUID> = []
    init(storage: (any DastakMerchantMenuDraftStorage)? = nil) { self.storage = storage }
    var usesDeviceStorage: Bool { storage != nil && accountID != nil }
    var needsRestoreRetry: Bool { restoreBlocked }
    func setAccount(_ account: UUID?) { if accountID != account { clear(); accountID = account } }
    var dirtyCount: Int { records.values.filter { $0.dirty || $0.stale }.count + additions.values.filter(\.dirty).count + (composer.dirty ? 1 : 0) }
    var unavailable: [DastakMerchantMenuDraft] { records.values.filter { $0.latest == nil && $0.dirty }.sorted { $0.value.name < $1.value.name } }
    var unavailableAdditions: [(UUID, DastakMerchantMenuAddition)] { additions.filter { !parents.contains($0.key) && $0.value.dirty }.sorted { $0.key.uuidString < $1.key.uuidString } }
    func reconcile(_ menu: DastakV1RestaurantMenu?) {
        guard let menu else { clear(); return }
        if branchID != menu.restaurant.branchID {
            clear(); branchID = menu.restaurant.branchID
            if let storage, let accountID, let branchID {
                do {
                    if let saved = try storage.load(account: accountID, branch: branchID) {
                        revision = saved.revision; lastSaved = saved; records = saved.records; additions = saved.additions; composer = saved.composer
                    }
                } catch {
                    restoreBlocked = true
                    persistenceFailure = "Saved drafts could not be read. The stored file is untouched. Copy any new text before discarding local drafts for this store."
                }
            }
        }
        var sources: [UUID: DastakMerchantMenuSource] = [:]; parents = []
        for category in menu.categories {
          sources[category.id] = .category(category)
          for item in category.items {
            sources[item.id] = .item(item, categoryID: category.id); parents.insert(item.id)
            for group in item.optionGroups {
                sources[group.id] = .group(group, itemID: item.id); parents.insert(group.id)
                for option in group.options { sources[option.id] = .option(option, groupID: group.id) }
            }
        } }
        var next = records
        for (id, source) in sources {
            if var draft = next[id] { draft.reconcile(source); next[id] = draft }
            else { next[id] = .init(source) }
        }
        for id in next.keys where sources[id] == nil {
            if next[id]?.dirty == true { next[id]?.reconcile(nil) } else { next[id] = nil }
        }
        records = next
        persist()
    }
    func edit(_ id: UUID, _ field: WritableKeyPath<DastakMerchantMenuFields, String>, _ value: String) { records[id]?.value[keyPath: field] = value; persist() }
    func useLatest(_ id: UUID) { records[id]?.useLatest(); persist() }
    func keepAfterReview(_ id: UUID) { records[id]?.keepAfterReview(); persist() }
    @discardableResult func resolve(_ id: UUID, reviewed: DastakMerchantMenuSource, keepText: Bool) -> Bool {
        guard records[id]?.latest == reviewed else { return false }
        if keepText { records[id]?.keepAfterReview() } else { records[id]?.useLatest() }
        persist(); return true
    }
    func discardUnavailable(_ id: UUID) { if records[id]?.latest == nil { records[id] = nil }; if !parents.contains(id) { additions[id] = nil }; persist() }
    func addition(_ id: UUID) -> DastakMerchantMenuAddition { additions[id] ?? .init() }
    func editAddition(_ id: UUID, _ value: DastakMerchantMenuAddition) { additions[id] = value; persist() }
    func clearAddition(_ id: UUID, submitted: DastakMerchantMenuAddition) { if additions[id] == submitted { additions[id] = nil; persist() } }
    func editComposer(_ value: DastakMerchantMenuComposer) { composer = value; persist() }
    func acknowledgeCreation(_ payload: DastakV1RestaurantMenuPayload) {
        // Also used after a saved creation is recovered, when its originating
        // view's async callback is no longer alive. Do not leave a duplicate-ready form.
        switch payload {
        case let .category(name, _, _, _):
            if composer.categoryName.trimmingCharacters(in: .whitespacesAndNewlines) == name { composer.categoryName = "" }
        case let .item(categoryID, name, _, _, price, _, _, _):
            if composer.itemCategoryID == categoryID, composer.itemName.trimmingCharacters(in: .whitespacesAndNewlines) == name,
               DastakMerchantPriceParser.optionalPaise(from: composer.itemPrice) == price {
                composer.itemName = ""; composer.itemPrice = ""; composer.itemCategoryID = nil
            }
        case let .optionGroup(itemID, name, type, minimum, maximum, _, _):
            if let draft = additions[itemID], draft.name.trimmingCharacters(in: .whitespacesAndNewlines) == name,
               draft.selectionType == type, draft.minimumSelections == minimum, draft.maximumSelections == maximum { additions[itemID] = nil }
        case let .option(groupID, name, price, _, _):
            if let draft = additions[groupID], draft.name.trimmingCharacters(in: .whitespacesAndNewlines) == name,
               DastakMerchantPriceParser.optionalNonnegativePaise(from: draft.price) == price { additions[groupID] = nil }
        }
        persist()
    }
    func acknowledge(entityID: UUID, expectedVersion: Int, payload: DastakV1RestaurantMenuPayload) {
        guard let branchID, var draft = records[entityID], let latest = draft.latest,
              latest.version > expectedVersion, latest.payload == payload else { return }
        // A later local edit must survive an earlier command acknowledgement.
        var reviewed = draft; reviewed.keepAfterReview()
        guard reviewed.command(branchID: branchID)?.payload == payload else { return }
        draft.useLatest(); records[entityID] = draft; persist()
    }
    func clear() { branchID = nil; records = [:]; additions = [:]; parents = []; composer = .init(); revision = nil; lastSaved = nil; restoreBlocked = false; persistenceFailure = nil }
    private func persist() { do { try flush() } catch {
        if !restoreBlocked { persistenceFailure = "Drafts are retained in this workspace, but could not be saved on this device. Retry draft storage before closing the app. Another workspace may have newer drafts." }
    } }
    func retryPersistence() { persist() }
    func retryRestoring(_ menu: DastakV1RestaurantMenu) {
        guard restoreBlocked, dirtyCount == 0, branchID == menu.restaurant.branchID else { return }
        clear(); reconcile(menu)
    }
    func flush() throws {
        guard let storage else { return }
        guard !restoreBlocked, let accountID, let branchID else { throw DastakAdminExecutionError.changed }
        let dirty = records.filter { $0.value.dirty || $0.value.stale }
        let additions = additions.filter { $0.value.dirty }
        // Avoid creating empty files or changing a clean read's revision.
        if revision == nil && dirty.isEmpty && additions.isEmpty && !composer.dirty { persistenceFailure = nil; return }
        if let lastSaved, dirty == lastSaved.records, additions == lastSaved.additions, composer == lastSaved.composer {
            guard try storage.load(account: accountID,branch: branchID)?.revision == revision else { throw DastakAdminExecutionError.changed }
            persistenceFailure = nil; return
        }
        let archive = DastakMerchantMenuDraftArchive(accountID: accountID, branchID: branchID, records: dirty, additions: additions, composer: composer)
        try storage.replace(archive, expectedRevision: revision)
        revision = archive.revision; lastSaved = archive; persistenceFailure = nil
    }
    func discardLocalDrafts(_ menu: DastakV1RestaurantMenu) {
        guard let storage, let accountID, branchID == menu.restaurant.branchID else { return }
        do {
            try storage.discard(account: accountID, branch: menu.restaurant.branchID)
            clear(); reconcile(menu)
        } catch { persistenceFailure = "Local drafts could not be discarded. The saved action journal and live menu are unchanged." }
    }
}

enum DastakMerchantMenuSearch {
    static func categories(_ categories: [DastakV1RestaurantMenuCategory], query: String) -> [DastakV1RestaurantMenuCategory] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }
        return categories.filter { category in category.name.localizedCaseInsensitiveContains(query) || (category.description ?? "").localizedCaseInsensitiveContains(query)
            || category.items.contains { matches($0, query: query) } }
    }
    static func items(_ category: DastakV1RestaurantMenuCategory, query: String) -> [DastakV1RestaurantMenuItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty || category.name.localizedCaseInsensitiveContains(query) || (category.description ?? "").localizedCaseInsensitiveContains(query) { return category.items }
        return category.items.filter { matches($0, query: query) }
    }
    private static func matches(_ item: DastakV1RestaurantMenuItem, query: String) -> Bool {
        [item.name, item.description ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
            || item.optionGroups.contains { group in group.name.localizedCaseInsensitiveContains(query) || group.options.contains { $0.name.localizedCaseInsensitiveContains(query) } }
    }
}
