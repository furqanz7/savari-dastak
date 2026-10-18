import SwiftUI
import MarketplaceDesignSystem
import MarketplaceInfrastructure

struct DastakMerchantMenuDishEditor: View {
    @ObservedObject var model: DastakMerchantModel
    @ObservedObject var drafts: DastakMerchantMenuDraftStore
    let item: DastakV1RestaurantMenuItem
    let branchID: UUID?
    private var addition: DastakMerchantMenuAddition { drafts.addition(item.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let draft = drafts.records[item.id] {
                Text(item.name).font(.headline)
                Text(item.status == "ACTIVE" ? "Available" : "Hidden from new orders").font(.caption).foregroundStyle(.secondary)
                DastakMerchantMediaPicker(title: "Dish photo", message: draft.dirty ? "Save or discard text edits before changing this photo." : "Optional. Use a clear photo of the dish.", imageKey: item.imageKey,
                    compact: true, busy: model.restaurantChangesDisabled || draft.dirty || draft.stale) { media in
                    guard branchID == model.restaurantMenu?.restaurant.branchID else {
                        model.errorMessage = DastakMerchantStoreReadError.wrongLocation.message; return false
                    }
                    return await model.uploadRestaurantMedia(entityType: "RESTAURANT_MENU_ITEM", entityID: item.id, expectedMediaVersion: item.mediaVersion ?? 1,
                        data: media.data, contentType: media.contentType, fileName: media.fileName)
                }
                if draft.dirty || draft.stale {
                    Label(draft.stale ? "Latest details need review" : "Unsaved dish changes", systemImage: draft.stale ? "exclamationmark.circle" : "pencil.circle")
                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("Edit dish details") {
                    DastakMerchantMenuFieldsEditor(model: model, drafts: drafts, entityID: item.id, branchID: branchID, isDish: true, status: item.status)
                        .padding(.top, 12)
                }.font(.subheadline.weight(.semibold)).padding(.vertical, 6)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(item.optionGroups) { group in
                        DastakMerchantMenuChoiceGroup(model: model, drafts: drafts, itemID: item.id, group: group, branchID: branchID)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New choice group").font(.headline)
                        Text("For example, choose a size or add extras. New groups start optional. After adding options, edit the group rules to make a choice required.").font(.caption).foregroundStyle(.secondary)
                        TextField("Choice name", text: additionBinding(\.name)).textFieldStyle(.roundedBorder)
                        if !addition.name.isEmpty && !addition.validName { Text("Use 1–100 characters for the choice name.").font(.caption).foregroundStyle(.secondary) }
                        Picker("How customers choose", selection: additionBinding(\.selectionType)) {
                            Text("One option").tag("SINGLE"); Text("Multiple options").tag("MULTIPLE")
                        }.pickerStyle(.menu)
                        if addition.selectionType == "MULTIPLE" {
                            TextField("Maximum selections", text: additionBinding(\.maximum)).textFieldStyle(.roundedBorder).merchantMenuNumberKeyboard()
                            Text("Customers can select up to this many active options. Enter a whole number of at least 1.").font(.caption).foregroundStyle(.secondary)
                            if addition.maximumSelections == nil { Text("Enter a supported positive whole number.").font(.caption).foregroundStyle(.secondary) }
                        }
                        Button("Add choice group", systemImage: "plus") {
                            let submitted = addition
                            guard submitted.validName, let max = submitted.maximumSelections else {
                                model.errorMessage = "Enter a choice name from 1 to 100 characters and a whole-number maximum of at least 1."; return
                            }
                            Task {
                                if await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0,
                                    payload: .optionGroup(menuItemID: item.id, name: submitted.name.trimmingCharacters(in: .whitespacesAndNewlines), selectionType: submitted.selectionType,
                                                          minimumSelections: 0, maximumSelections: max, sortOrder: item.optionGroups.count, status: "ACTIVE"), branchID: branchID) {
                                    drafts.clearAddition(item.id, submitted: submitted)
                                }
                            }
                        }.buttonStyle(DastakMerchantActionStyle()).disabled(model.restaurantChangesDisabled || !addition.validName || addition.maximumSelections == nil)
                    }.disabled(model.restaurantChangesDisabled)
                }.padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Customer choices & extras").font(.headline)
                    Text("Edit sizes, flavours, options and extra prices").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 12)
    }
    private func additionBinding(_ field: WritableKeyPath<DastakMerchantMenuAddition, String>) -> Binding<String> {
        Binding(get: { addition[keyPath: field] }, set: { var value = addition; value[keyPath: field] = $0; drafts.editAddition(item.id, value) })
    }
}

private struct DastakMerchantMenuChoiceGroup: View {
    @ObservedObject var model: DastakMerchantModel
    @ObservedObject var drafts: DastakMerchantMenuDraftStore
    let itemID: UUID
    let group: DastakV1RestaurantMenuOptionGroup
    let branchID: UUID?
    private var addition: DastakMerchantMenuAddition { drafts.addition(group.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.name).font(.headline)
            Text("\(group.minimumSelections)–\(group.maximumSelections) selections · \(group.status.lowercased())").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Edit choice rules & display order") {
                DastakMerchantMenuFieldsEditor(model: model,drafts: drafts,entityID: group.id,branchID: branchID,isDish: false,status: group.status)
                    .padding(.top,12)
                Text("\(group.options.filter { $0.status == "ACTIVE" }.count) active options. Customers must be able to meet the minimum using active options; hidden groups are not offered.")
                    .font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline.weight(.semibold)).padding(.vertical,6)
            ForEach(group.options) { option in
                VStack(alignment: .leading, spacing: 8) {
                    Text(option.status == "ACTIVE" ? "Active extra" : "Hidden extra").font(.caption).foregroundStyle(.secondary)
                    DastakMerchantMenuFieldsEditor(model: model, drafts: drafts, entityID: option.id, branchID: branchID, isDish: false, status: option.status)
                }.padding(12).marketplaceFlatSurface()
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("New option").font(.subheadline.bold())
                TextField("Option name", text: additionBinding(\.name)).textFieldStyle(.roundedBorder)
                if !addition.name.isEmpty && !addition.validName { Text("Use 1–100 characters for the option name.").font(.caption).foregroundStyle(.secondary) }
                TextField("Additional price in rupees", text: additionBinding(\.price)).textFieldStyle(.roundedBorder).merchantMenuDecimalKeyboard()
                if DastakMerchantPriceParser.optionalNonnegativePaise(from: addition.price) == nil {
                    Text(DastakMerchantValidation.extraPriceHelp).font(.caption).foregroundStyle(.secondary)
                }
                Button("Add option", systemImage: "plus") {
                    let submitted = addition
                    guard submitted.validName, let price = DastakMerchantPriceParser.optionalNonnegativePaise(from: submitted.price) else {
                        model.errorMessage = "Enter an option name from 1 to 100 characters. " + DastakMerchantValidation.extraPriceHelp; return
                    }
                    Task {
                        if await model.saveRestaurantEntity(entityID: nil, expectedVersion: 0,
                            payload: .option(optionGroupID: group.id, name: submitted.name.trimmingCharacters(in: .whitespacesAndNewlines), priceDeltaPaise: price,
                                             sortOrder: group.options.count, status: "ACTIVE"), branchID: branchID) { drafts.clearAddition(group.id, submitted: submitted) }
                    }
                }.buttonStyle(DastakMerchantActionStyle()).disabled(model.restaurantChangesDisabled || !addition.validName || DastakMerchantPriceParser.optionalNonnegativePaise(from: addition.price) == nil)
            }.disabled(model.restaurantChangesDisabled)
        }.padding(14).background(MarketplaceColors.dastakAccentSoft.color.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
    private func additionBinding(_ field: WritableKeyPath<DastakMerchantMenuAddition, String>) -> Binding<String> {
        Binding(get: { addition[keyPath: field] }, set: { var value = addition; value[keyPath: field] = $0; drafts.editAddition(group.id, value) })
    }
}

struct DastakMerchantMenuCategoryEditor: View {
    @ObservedObject var model: DastakMerchantModel
    @ObservedObject var drafts: DastakMerchantMenuDraftStore
    let category: DastakV1RestaurantMenuCategory
    let branchID: UUID?
    var body: some View {
        DisclosureGroup("Edit category & display order") {
            DastakMerchantMenuFieldsEditor(model: model,drafts: drafts,entityID: category.id,branchID: branchID,isDish: false,status: category.status)
                .padding(.top,12)
        }.font(.subheadline.weight(.semibold)).padding(.vertical,6)
    }
}

private struct DastakMerchantMenuFieldsEditor: View {
    @ObservedObject var model: DastakMerchantModel
    @ObservedObject var drafts: DastakMerchantMenuDraftStore
    let entityID: UUID
    let branchID: UUID?
    let isDish: Bool
    let status: String
    @State private var review: Review?
    private struct Review { let keepText: Bool; let source: DastakMerchantMenuSource }
    var body: some View {
        if let draft = drafts.records[entityID] {
            let kind = draft.baseline.payload.entityType
            let category = kind == "CATEGORY", group = kind == "OPTION_GROUP"
            let entry = isDish ? "dish" : category ? "category" : group ? "choice group" : "extra"
            VStack(alignment: .leading, spacing: 10) {
                if draft.stale {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("New server details need review", systemImage: "exclamationmark.triangle").font(.subheadline.bold())
                        Text("Your edits are retained below. Saving and availability changes are paused; the old draft will not be sent with a new version automatically.").font(.caption)
                        if let latest = draft.latest {
                            Text("Latest: \(latest.fields.name)\(category || group ? "" : " · ₹" + latest.fields.price)\n\(latest.fields.description)").font(.subheadline).textSelection(.enabled)
                            if category || group { Text("Latest display order · \(latest.fields.order)").font(.caption) }
                            if group { Text("Latest choices · \(latest.fields.selectionType) · minimum \(latest.fields.minimum), maximum \(latest.fields.maximum)").font(.caption) }
                            Text("Latest availability · \(latest.status.lowercased())").font(.caption)
                            Text("Latest entity version \(latest.version). Unedited parent, photo, tax, logistics and availability metadata use the reviewed latest record.").font(.caption).foregroundStyle(.secondary)
                            Button("Use latest and discard my edits") { review = .init(keepText: false, source: latest) }.frame(minHeight: 44)
                            Button("Keep my edits after reviewing latest") { review = .init(keepText: true, source: latest) }.frame(minHeight: 44)
                        }
                    }.padding(12).marketplaceFlatSurface().accessibilityIdentifier("merchant.menu.stale.\(entityID)")
                }
                TextField(isDish ? "Dish name" : category ? "Category name" : group ? "Choice group name" : "Option name", text: field(\.name)).textFieldStyle(.roundedBorder)
                if isDish || category { TextField("Description", text: field(\.description), axis: .vertical).textFieldStyle(.roundedBorder) }
                if !category && !group { TextField(isDish ? "Price in rupees" : "Additional price in rupees", text: field(\.price)).textFieldStyle(.roundedBorder).merchantMenuDecimalKeyboard() }
                if category || group {
                    TextField("Display order",text: field(\.order)).textFieldStyle(.roundedBorder)
                    Text("Use a whole number. Smaller display orders appear first; equal values retain the server's stable ordering.").font(.caption).foregroundStyle(.secondary)
                }
                if group {
                    Picker("How customers choose",selection: Binding(get: { draft.value.selectionType },set: {
                        drafts.edit(entityID,\.selectionType,$0)
                        if $0 == "SINGLE" { drafts.edit(entityID,\.maximum,"1") }
                    })) {
                        Text("One option").tag("SINGLE"); Text("Multiple options").tag("MULTIPLE")
                    }.pickerStyle(.menu)
                    TextField("Minimum selections",text: field(\.minimum)).textFieldStyle(.roundedBorder).merchantMenuNumberKeyboard()
                    TextField("Maximum selections",text: field(\.maximum)).textFieldStyle(.roundedBorder).merchantMenuNumberKeyboard()
                    Text("Minimum 0 makes this optional. Minimum 1 or more makes it required. A single-choice group has maximum 1.").font(.caption).foregroundStyle(.secondary)
                }
                if let validation = draft.validation { Text(validation).font(.caption).foregroundStyle(.secondary) }
                if draft.dirty { Text("Unsaved changes").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 10) {
                    MarketplaceFeedbackButton("Save \(entry) changes") { save() }
                        .buttonStyle(DastakMerchantActionStyle(primary: true)).disabled(!draft.canSave || !draft.dirty || model.restaurantChangesDisabled)
                        .accessibilityIdentifier("merchant.menu.save.\(entityID)")
                    MarketplaceFeedbackButton(status == "ACTIVE" ? (isDish ? "Mark unavailable" : category ? "Hide category" : group ? "Hide group" : "Hide extra") : "Activate") {
                        save(status: status == "ACTIVE" ? "INACTIVE" : "ACTIVE")
                    }.buttonStyle(DastakMerchantActionStyle()).disabled(!draft.canSave || draft.dirty || model.restaurantChangesDisabled)
                    if draft.dirty && !draft.stale, let latest = draft.latest { Button("Discard edits", role: .destructive) { review = .init(keepText: false, source: latest) }.frame(minHeight: 44) }
                }
                if draft.dirty { Text("Save or discard edits before changing availability.").font(.caption).foregroundStyle(.secondary) }
            }
            .disabled(model.restaurantChangesDisabled)
            .confirmationDialog("Review retained menu draft", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), titleVisibility: .visible) {
                if let review {
                    Button(review.keepText ? "Keep my edits against reviewed latest version" : "Discard my edits and use latest", role: review.keepText ? nil : .destructive) {
                        if !drafts.resolve(entityID, reviewed: review.source, keepText: review.keepText) { model.notice = "Menu details changed again. Review the new latest values before continuing." }
                        self.review = nil
                    }
                }
                Button("Cancel", role: .cancel) { review = nil }
            } message: { Text("\(review?.source.fields.name ?? "Entry unavailable"). Keeping edits does not save them. Review the latest fields above, then tap Save separately.") }
        }
    }
    private func field(_ path: WritableKeyPath<DastakMerchantMenuFields, String>) -> Binding<String> {
        Binding(get: { drafts.records[entityID]?.value[keyPath: path] ?? "" }, set: { drafts.edit(entityID, path, $0) })
    }
    private func save(status: String? = nil) {
        guard let branchID, drafts.branchID == branchID, let command = drafts.records[entityID]?.command(branchID: branchID, status: status) else {
            model.errorMessage = drafts.records[entityID]?.validation ?? "This menu draft is not ready to save. Review the latest entry and save or discard text edits before changing availability."
            return
        }
        Task { _ = await model.saveRestaurantEntity(entityID: command.entityID, expectedVersion: command.expectedVersion, payload: command.payload, branchID: command.branchID) }
    }
}

private extension View {
    @ViewBuilder func merchantMenuDecimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
    @ViewBuilder func merchantMenuNumberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
