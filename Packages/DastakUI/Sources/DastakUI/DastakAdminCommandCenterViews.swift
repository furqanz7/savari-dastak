import Foundation
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakAdminOverviewView: View {
    @ObservedObject var model: DastakOwnerOperationsModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    commandHero
                    if !model.workspaceIssues.isEmpty {
                        DastakAdminRefreshSummaryCard(
                            issues: model.workspaceIssues,
                            isRefreshing: model.isRefreshing
                        ) {
                            Task {
                                for issue in model.workspaceIssues {
                                    await model.retry(issue.workspace)
                                }
                            }
                        }
                    }
                    if let snapshot = model.commandCenter {
                        metrics(snapshot)
                        actionQueue(snapshot)
                        fulfilment(snapshot)
                        Text("Observed \(adminDate(snapshot.observedAt))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if model.isLoading {
                        ProgressView("Connecting marketplace signals")
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ContentUnavailableView(
                            "Command center unavailable",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("Orders and specialist workspaces remain available.")
                        )
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(MarketplaceSpacing.large)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Command center")
            .refreshable { await model.refresh(.commandCenter) }
        }
        .marketplacePage()
    }

    private var commandHero: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack {
                Label("LIVE OPERATIONS", systemImage: "waveform.path.ecg")
                    .font(.caption.bold())
                    .tracking(1.4)
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
            }
            Text("The whole marketplace, in one view.")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 44))
                .fixedSize(horizontal: false, vertical: true)
            Text("Identity, fulfilment, delivery, safety and catalogue signals are connected to authoritative Dastak records.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .padding(MarketplaceSpacing.large)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.12, blue: 0.09), Color(red: 0.28, green: 0.21, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func metrics(_ snapshot: DastakAdminCommandCenter) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MarketplaceSpacing.compact) {
            AdminMetric(title: "Active orders", value: snapshot.commerce.activeOrders, detail: "\(snapshot.commerce.deliveredToday) delivered today", symbol: "shippingbox.fill")
            AdminMetric(title: "Active accounts", value: snapshot.identities.activeAccounts, detail: "\(snapshot.identities.customers) customers", symbol: "person.2.fill")
            AdminMetric(title: "Riders online", value: snapshot.network.onlineRiders, detail: "\(snapshot.network.assignedRiders) assigned", symbol: "motorcycle")
            AdminMetric(title: "Active catalogue", value: snapshot.catalogue.active, detail: "\(snapshot.catalogue.needsReview) need QA", symbol: "square.grid.3x3.fill")
        }
    }

    private func actionQueue(_ snapshot: DastakAdminCommandCenter) -> some View {
        let queue = snapshot.actionQueue
        return VStack(alignment: .leading, spacing: 0) {
            AdminSectionHeader(eyebrow: "ACTION QUEUE", title: "Needs attention")
            AdminQueueRow(title: "Merchant applications", count: queue.merchantApplications, symbol: "storefront")
            AdminQueueRow(title: "Delivery applications", count: queue.deliveryApplications, symbol: "motorcycle")
            AdminQueueRow(title: "Safety escalations", count: queue.riderEscalations + queue.activePauses, symbol: "exclamationmark.shield")
            AdminQueueRow(title: "System incidents", count: queue.openIncidents, symbol: "waveform.path.ecg")
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private func fulfilment(_ snapshot: DastakAdminCommandCenter) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            AdminSectionHeader(eyebrow: "FULFILMENT FLOW", title: "Live pipeline")
            FlowRow(title: "Awaiting confirmation", value: snapshot.commerce.awaitingPayment)
            FlowRow(title: "Preparing", value: snapshot.commerce.preparingFulfilments)
            FlowRow(title: "Ready for pickup", value: snapshot.commerce.readyFulfilments)
            FlowRow(title: "Active delivery missions", value: snapshot.commerce.activeMissions)
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

}

struct DastakAdminApprovalsView: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    @State private var selected: AdminReviewTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    AdminPageIntro(eyebrow: "GOVERNED ONBOARDING", title: "Application approvals", detail: "Review each business and identity submission before a persona becomes operational.")
                    workspaceIssue(.merchantApprovals)
                    workspaceIssue(.deliveryApprovals)
                    approvalGroup(
                        "Merchant applications",
                        count: model.merchantApplications.count,
                        workspace: .merchantApprovals
                    ) {
                        ForEach(model.merchantApplications, id: \.applicationID) { application in
                            Button { selected = .merchant(application) } label: {
                                AdminApprovalRow(
                                    title: application.businessName,
                                    detail: "\(application.merchantType.displayName) · \(application.serviceZoneName)",
                                    symbol: application.merchantType == .restaurantCafe ? "fork.knife" : "storefront"
                                )
                            }.buttonStyle(.plain)
                        }
                    }
                    approvalGroup(
                        "Delivery Partner applications",
                        count: model.deliveryApplications.count,
                        workspace: .deliveryApprovals
                    ) {
                        ForEach(model.deliveryApplications, id: \.applicationID) { application in
                            Button { selected = .delivery(application) } label: {
                                AdminApprovalRow(title: application.displayName, detail: "\(application.deliveryMethod.displayName) · \(application.phoneNumber)", symbol: "motorcycle")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                .padding(MarketplaceSpacing.large)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Approvals")
            .refreshable { await model.refresh([.merchantApprovals, .deliveryApprovals]) }
        }
        .marketplacePage()
        .sheet(item: $selected) { target in
            AdminReviewSheet(target: target, model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func workspaceIssue(_ workspace: DastakAdminWorkspace) -> some View {
        if let issue = model.issue(for: workspace) {
            DastakAdminWorkspaceIssueCard(
                issue: issue,
                lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: workspace),
                isRefreshing: model.isRefreshing
            ) { Task { await model.retry(workspace) } }
        }
    }

    private func approvalGroup<Content: View>(
        _ title: String,
        count: Int,
        workspace: DastakAdminWorkspace,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            HStack { Text(title).font(.title3.bold()); Spacer(); Text("\(count)").font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5).background(MarketplaceColors.dastakAccentSoft.color, in: Capsule()) }
            if count == 0 {
                Label(
                    model.issue(for: workspace) != nil && model.lastSuccessfulRefresh(for: workspace) == nil
                        ? "Application count is not available yet"
                        : "No applications waiting",
                    systemImage: model.issue(for: workspace) != nil && model.lastSuccessfulRefresh(for: workspace) == nil
                        ? "wifi.exclamationmark"
                        : "checkmark.circle.fill"
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .marketplaceFlatSurface()
            } else { content() }
        }
    }
}

struct DastakAdminNetworkView: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    @State private var query = ""
    @State private var persona: DastakAdminPersona?
    @State private var state: DastakAdminPersonaState?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Persona", selection: $persona) {
                        Text("All personas").tag(DastakAdminPersona?.none)
                        Text("Customers").tag(DastakAdminPersona?.some(.customer))
                        Text("Merchants").tag(DastakAdminPersona?.some(.merchant))
                        Text("Delivery Partners").tag(DastakAdminPersona?.some(.delivery))
                        Text("Admins").tag(DastakAdminPersona?.some(.admin))
                    }
                    Picker("State", selection: $state) {
                        Text("Any state").tag(DastakAdminPersonaState?.none)
                        Text("Active").tag(DastakAdminPersonaState?.some(.active))
                        Text("Deleted / recoverable").tag(DastakAdminPersonaState?.some(.deleted))
                    }
                }
                if let issue = model.issue(for: .network) {
                    Section {
                        DastakAdminWorkspaceIssueCard(
                            issue: issue,
                            lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: .network),
                            isRefreshing: model.isLoadingNetwork
                        ) { Task { await load() } }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if model.isLoadingNetwork, model.networkPeople.isEmpty {
                    HStack { Spacer(); ProgressView("Connecting identities"); Spacer() }.listRowBackground(Color.clear)
                } else if model.networkPeople.isEmpty,
                          model.issue(for: .network) == nil || model.lastSuccessfulRefresh(for: .network) != nil {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("Connected identities") {
                        ForEach(model.networkPeople) { person in
                            NavigationLink { AdminPersonDetail(person: person) } label: { AdminPersonRow(person: person) }
                        }
                        if model.networkHasMore {
                            Button("Load more identities") { Task { await load(append: true) } }
                                .frame(maxWidth: .infinity)
                                .disabled(model.isLoadingNetwork)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle("Network")
            .searchable(text: $query, prompt: "Name, email or phone")
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: persona) { Task { await load() } }
            .onChange(of: state) { Task { await load() } }
            .task { if model.networkPeople.isEmpty { await load() } }
            .refreshable { await load() }
        }
        .marketplacePage()
    }

    private func load(append: Bool = false) async {
        await model.loadNetwork(query: query, persona: persona, state: state, append: append)
    }
}

struct DastakAdminMoreView: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    let services: MarketplaceAuthenticatedServices

    var body: some View {
        NavigationStack {
            List {
                Section("Marketplace control") {
                    NavigationLink { DastakAdminCatalogueView(model: model) } label: { MoreRow(title: "Master catalogue", detail: "Exact SKUs, QA, pricing and visibility", symbol: "square.grid.3x3") }
                    NavigationLink { DastakAdminGovernanceView(model: model) } label: { MoreRow(title: "Safety & system health", detail: "Pauses, escalations and invariant signals", symbol: "checkmark.shield") }
                    NavigationLink { DastakAdminFinanceView(model: model) } label: { MoreRow(title: "Finance & Royalty", detail: "Collection, fee and journal truth", symbol: "indianrupeesign.circle") }
                }
                Section("Access & account") {
                    if model.adminAccess?.canManageAdmins == true {
                        NavigationLink { DastakAdminAccessView(model: model) } label: { MoreRow(title: "Admin access", detail: "One permanent Superadmin · two Executive seats", symbol: "person.2.badge.gearshape") }
                    }
                    NavigationLink {
                        DastakIdentityAccountView(
                            roleName: model.adminAccess?.role.displayName ?? "Admin",
                            accessLabel: "Full operations access",
                            allowsAccountDeletion: false,
                            openWorkspace: {},
                            services: services
                        )
                    } label: { MoreRow(title: "My account", detail: "Profile, security and sessions", symbol: "person.text.rectangle") }
                }
            }
            .listStyle(.inset)
            .navigationTitle("More")
        }
        .marketplacePage()
    }
}

private struct DastakAdminCatalogueView: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    @State private var query = ""
    @State private var categoryTypeID: UUID?
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var status: String?
    @State private var qaStatus: String?
    @State private var selectedSKU: DastakAdminCatalogueSKU?
    @State private var showsFilters = false

    var body: some View {
        Group {
            if let selectedCategory {
                selectedCategoryBrowser(selectedCategory)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                        catalogueIntroduction
                        catalogueToolbar
                        if categoryID == nil && trimmedQuery.isEmpty && status == nil && qaStatus == nil {
                            departmentDirectory
                        } else if shouldShowProducts {
                            catalogueResults
                        }
                    }
                    .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
                    .padding(MarketplaceSpacing.medium)
                    .padding(.bottom, 132)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Catalogue")
        .searchable(text: $query, prompt: "SKU, brand, alias or category")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: categoryTypeID) {
            if let categoryID, !visibleCategories.contains(where: { $0.id == categoryID }) {
                self.categoryID = nil
                subcategoryID = nil
            }
        }
        .onChange(of: categoryID) {
            subcategoryID = nil
            Task { await load() }
        }
        .onChange(of: subcategoryID) { Task { await load() } }
        .onChange(of: status) { Task { await load() } }
        .onChange(of: qaStatus) { Task { await load() } }
        .task { if model.catalogueSKUs.isEmpty { await load() } }
        .task(id: priorityArtworkKeys) {
            await DastakProductArtwork.prefetch(imageKeys: priorityArtworkKeys)
        }
        .marketplacePage()
        .sheet(item: $selectedSKU) { sku in
            AdminSKUEditor(sku: sku, model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsFilters) {
            NavigationStack {
                ScrollView { catalogueFilters.padding(MarketplaceSpacing.medium) }
                    .navigationTitle("Catalogue filters")
                    .dastakInlineNavigationTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsFilters = false } } }
            }
            .marketplacePage()
            .presentationDetents([.medium, .large])
        }
    }

    private var catalogueIntroduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MASTER CATALOGUE")
                .font(.caption2.bold())
                .tracking(1.3)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Everything, beautifully organised")
                .font(.title.bold())
                .lineLimit(2)
            Text("The same image-led catalogue customers and merchants browse.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectedCategoryBrowser(
        _ category: DastakAdminCatalogueTaxonomy.Category
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MASTER CATALOGUE")
                            .font(.caption2.bold())
                            .tracking(1.1)
                            .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        Text(model.catalogueTaxonomy?.categoryTypes.first { $0.id == categoryTypeID }?.name ?? category.name)
                            .font(.title3.bold())
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button("Filters", systemImage: "line.3.horizontal.decrease") { showsFilters = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("All categories") {
                        categoryTypeID = nil
                        categoryID = nil
                        subcategoryID = nil
                        status = nil
                        qaStatus = nil
                        query = ""
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(visibleSubcategories.first { $0.id == subcategoryID }?.name ?? category.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(model.catalogueSKUs.count) loaded")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.vertical, MarketplaceSpacing.small)

            Divider()

            HStack(alignment: .top, spacing: 8) {
                ScrollView(.vertical) {
                    selectedCategoryRail
                        .padding(.vertical, MarketplaceSpacing.small)
                        .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .frame(width: 76)

                ScrollView(.vertical) {
                    catalogueResults
                        .padding(.vertical, MarketplaceSpacing.small)
                        .padding(.bottom, 132)
                }
                .scrollIndicators(.hidden)
                .refreshable { await load() }
                .frame(maxWidth: .infinity)
                .id(categoryID)
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowProducts: Bool {
        categoryID != nil || subcategoryID != nil || !trimmedQuery.isEmpty || status != nil || qaStatus != nil
    }

    private var selectedCategory: DastakAdminCatalogueTaxonomy.Category? {
        model.catalogueTaxonomy?.categories.first { $0.id == categoryID }
    }

    private var catalogueToolbar: some View {
        HStack(spacing: 8) {
            Button("Filters", systemImage: "line.3.horizontal.decrease") { showsFilters = true }
                .buttonStyle(.bordered)
            if shouldShowProducts || categoryTypeID != nil {
                Button {
                    categoryTypeID = nil
                    categoryID = nil
                    subcategoryID = nil
                    status = nil
                    qaStatus = nil
                    query = ""
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Show all categories")
            }
            Spacer()
            if let taxonomy = model.catalogueTaxonomy {
                Text("\(taxonomy.categories.count) categories · \(taxonomy.subcategories.count) collections")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    @ViewBuilder
    private var departmentDirectory: some View {
        if let taxonomy = model.catalogueTaxonomy {
            ForEach(adminNavigationGroups(taxonomy), id: \.key) { group in
                VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
                    Text(group.name).font(.title3.bold())
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        alignment: .leading,
                        spacing: MarketplaceSpacing.medium
                    ) {
                        ForEach(group.types) { type in
                            Button {
                                categoryTypeID = type.id
                                let children = taxonomy.categories.filter { $0.categoryTypeID == type.id }
                                categoryID = (children.first { $0.status == "ACTIVE" } ?? children.first)?.id
                                subcategoryID = nil
                            } label: {
                                AdminCatalogueDepartmentTile(categoryType: type)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } else if model.isLoadingCatalogue {
            ProgressView("Loading catalogue")
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    @ViewBuilder
    private var selectedCategoryRail: some View {
        if categoryID != nil {
            LazyVStack(spacing: MarketplaceSpacing.compact) {
                ForEach(visibleCategories) { category in
                    Button { categoryID = category.id; subcategoryID = nil } label: {
                        AdminCatalogueCollectionTile(
                            title: category.name,
                            imageKey: category.imageKey ?? categoryArtworkKey(category.id),
                            previewImageKeys: category.previewImageKeys,
                            selected: categoryID == category.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(categoryID == category.id ? .isSelected : [])
                }
            }
            .frame(width: 72)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var catalogueResults: some View {
        if let issue = model.issue(for: .catalogue) {
            DastakAdminWorkspaceIssueCard(
                issue: issue,
                lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: .catalogue),
                isRefreshing: model.isLoadingCatalogue
            ) { Task { await load() } }
        }

        if model.isLoadingCatalogue, model.catalogueSKUs.isEmpty {
            ProgressView("Loading exact SKUs")
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if model.catalogueSKUs.isEmpty,
                  model.issue(for: .catalogue) == nil || model.lastSuccessfulRefresh(for: .catalogue) != nil {
            ContentUnavailableView(
                "No exact SKUs found",
                systemImage: "shippingbox.and.arrow.backward",
                description: Text("Change a category, filter or search term.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
            .marketplaceFlatSurface()
        } else {
            AdminSectionHeader(eyebrow: "EXACT SKU LIBRARY", title: "Customer-ready products")
            adminProductGrid
            if model.catalogueHasMore {
                Button("Load next 40 products", systemImage: "chevron.down") {
                    Task { await load(append: true) }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(model.isLoadingCatalogue)
            }
        }
    }

    private var adminProductGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            alignment: .leading,
            spacing: MarketplaceSpacing.compact
        ) {
            ForEach(model.catalogueSKUs) { sku in
                Button { selectedSKU = sku } label: { AdminCatalogueGridCard(sku: sku) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func categoryArtworkKey(_ categoryID: UUID) -> String? {
        if let preview = model.catalogueTaxonomy?.categories.first(where: {
            $0.id == categoryID
        })?.previewImageKeys?.first {
            return preview
        }
        if let preview = model.catalogueTaxonomy?.skuPreviews?.first(where: {
            $0.categoryID == categoryID && $0.imageKey != nil
        })?.imageKey {
            return preview
        }
        return model.catalogueSKUs.first {
            $0.categoryID == categoryID && ($0.primaryImage?.imageKey ?? $0.imageKey) != nil
        }.flatMap { $0.primaryImage?.imageKey ?? $0.imageKey }
    }

    private var priorityArtworkKeys: [String] {
        var keys: [String] = []
        if categoryID != nil {
            if let key = selectedCategory.flatMap({ $0.imageKey ?? categoryArtworkKey($0.id) }) {
                keys.append(key)
            }
            keys.append(contentsOf: visibleCategories.compactMap {
                $0.imageKey ?? categoryArtworkKey($0.id)
            })
            keys.append(contentsOf: model.catalogueSKUs.prefix(16).compactMap {
                $0.primaryImage?.imageKey ?? $0.imageKey
            })
        } else {
            if categoryTypeID == nil {
                for type in model.catalogueTaxonomy?.categoryTypes ?? [] {
                    keys.append(contentsOf: ([type.imageKey].compactMap { $0 }
                        + (type.previewImageKeys ?? [])).prefix(2))
                }
            } else {
                for category in visibleCategories {
                    keys.append(contentsOf: ([category.imageKey].compactMap { $0 }
                        + (category.previewImageKeys ?? [])).prefix(2))
                }
            }
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }.prefix(32).map { $0 }
    }

    private var catalogueFilters: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            AdminSectionHeader(eyebrow: "CLASSIFICATION & READINESS", title: "Refine the library")
            Picker("Department", selection: $categoryTypeID) {
                Text("All departments").tag(UUID?.none)
                ForEach(model.catalogueTaxonomy?.categoryTypes ?? []) { value in
                    Text(value.name).tag(UUID?.some(value.id))
                }
            }
            Picker("Category", selection: $categoryID) {
                Text("All categories").tag(UUID?.none)
                ForEach(visibleCategories) { value in
                    Text(value.name).tag(UUID?.some(value.id))
                }
            }
            Picker("Subcategory", selection: $subcategoryID) {
                Text("All subcategories").tag(UUID?.none)
                ForEach(visibleSubcategories) { value in
                    Text(value.name).tag(UUID?.some(value.id))
                }
            }
            Picker("Visibility", selection: $status) {
                Text("Any visibility").tag(String?.none)
                Text("Active").tag(String?.some("ACTIVE"))
                Text("Draft").tag(String?.some("DRAFT"))
                Text("Inactive").tag(String?.some("INACTIVE"))
            }
            Picker("QA", selection: $qaStatus) {
                Text("Any QA state").tag(String?.none)
                Text("Verified").tag(String?.some("VERIFIED"))
                Text("Needs review").tag(String?.some("NEEDS_REVIEW"))
                Text("Pending").tag(String?.some("PENDING"))
                Text("Rejected").tag(String?.some("REJECTED"))
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
    }

    private var visibleCategories: [DastakAdminCatalogueTaxonomy.Category] {
        (model.catalogueTaxonomy?.categories ?? []).filter {
            categoryTypeID == nil || $0.categoryTypeID == categoryTypeID
        }
    }

    private var visibleSubcategories: [DastakAdminCatalogueTaxonomy.Subcategory] {
        let visibleIDs = Set(visibleCategories.map(\.id))
        return (model.catalogueTaxonomy?.subcategories ?? []).filter {
            (categoryID == nil || $0.categoryID == categoryID) && visibleIDs.contains($0.categoryID)
        }
    }

    private func adminNavigationGroups(
        _ taxonomy: DastakAdminCatalogueTaxonomy
    ) -> [AdminCatalogueNavigationGroup] {
        let grouped = Dictionary(grouping: taxonomy.categoryTypes) {
            $0.navigationSection?.key ?? "more"
        }
        return grouped.map { key, types in
            let metadata = types.compactMap(\.navigationSection).first
            return AdminCatalogueNavigationGroup(
                key: key,
                name: metadata?.name ?? "More to explore",
                sortOrder: metadata?.sortOrder ?? 999,
                types: types.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            )
        }
        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private func load(append: Bool = false) async {
        await model.loadCatalogue(
            query: query,
            categoryTypeID: categoryTypeID,
            categoryID: categoryID,
            subcategoryID: subcategoryID,
            status: status,
            qaStatus: qaStatus,
            append: append
        )
    }
}

private struct DastakAdminGovernanceView: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    @State private var createsPause = false
    @State private var resumedPause: DastakAdminOperationalSafety.Pause?
    @State private var selectedEscalation: DastakAdminOperationalSafety.RiderEscalation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                AdminPageIntro(eyebrow: "CONTROL & GOVERNANCE", title: "Safety and system health", detail: "Live operational controls stay permission-bound and every intervention remains audited.")
                workspaceIssue(.systemHealth)
                if let health = model.systemHealth {
                    AdminStateCard(
                        title: health.healthy ? "All monitored invariants are healthy" : "System health needs attention",
                        detail: "\(health.openCriticalIncidentCount) critical incidents · observed \(adminDate(health.observedAt))",
                        symbol: health.healthy ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                        attention: !health.healthy
                    )
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MarketplaceSpacing.compact) {
                        AdminMetric(title: "Outbox pending", value: health.outbox.pending, detail: "\(health.outbox.deadLetter) dead letter", symbol: "tray.full")
                        AdminMetric(title: "Notifications", value: health.notifications.pending, detail: "\(health.notifications.inFlight) in flight", symbol: "bell.badge")
                        AdminMetric(title: "Reconciliation", value: health.paymentReconciliationOpen, detail: "open payment cases", symbol: "arrow.triangle.2.circlepath")
                        AdminMetric(title: "Monitor findings", value: health.lastMonitorRun?.findingCount ?? 0, detail: health.workerConfigured ? "worker configured" : "worker unavailable", symbol: "waveform.path.ecg")
                    }
                    if !health.incidents.isEmpty {
                        governanceSection("OPEN INCIDENTS") {
                            ForEach(health.incidents.prefix(8)) { incident in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(incident.invariantKey.replacingOccurrences(of: "_", with: " ").capitalized).font(.headline)
                                    Text("\(incident.entityType.replacingOccurrences(of: "_", with: " ").capitalized) · \(String(incident.entityID.uuidString.prefix(8)).uppercased())")
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Text("Detected \(incident.occurrenceCount) time(s) · last \(adminDate(incident.lastDetectedAt))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(MarketplaceSpacing.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .marketplaceFlatSurface()
                            }
                        }
                    }
                } else if model.issue(for: .systemHealth) == nil {
                    ProgressView("Loading system health").frame(maxWidth: .infinity, minHeight: 120)
                }

                workspaceIssue(.operationalSafety)
                if let safety = model.operationalSafety {
                    HStack {
                        AdminSectionHeader(eyebrow: "OPERATIONAL SAFETY", title: "Protected controls")
                        Spacer()
                        if safety.permissions.canManageOperationalPauses {
                            Button("Create pause", systemImage: "pause.circle") { createsPause = true }
                                .buttonStyle(.borderedProminent)
                                .tint(MarketplaceColors.dastakAccent.color)
                        }
                    }
                    if safety.pauses.isEmpty {
                        ContentUnavailableView("No operational pauses", systemImage: "play.circle", description: Text("Marketplace intake and assignments are running normally."))
                            .frame(maxWidth: .infinity, minHeight: 150).marketplaceFlatSurface()
                    } else {
                        ForEach(safety.pauses) { pause in
                            HStack(alignment: .top, spacing: MarketplaceSpacing.medium) {
                                Image(systemName: pause.active ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title2).foregroundStyle(pause.active ? MarketplaceColors.warning.color : MarketplaceColors.success.color)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pause.scope.displayName).font(.headline)
                                    Text(pause.reason).font(.subheadline).foregroundStyle(.secondary)
                                    Text("Target \(String(pause.targetID.uuidString.prefix(8)).uppercased()) · version \(pause.version)")
                                        .font(.caption.monospaced()).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if pause.active, safety.permissions.canManageOperationalPauses {
                                    Button("Resume") { resumedPause = pause }.buttonStyle(.bordered)
                                }
                            }
                            .padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
                        }
                    }

                    governanceSection("RIDER ESCALATIONS") {
                        if safety.riderEscalations.isEmpty {
                            Label("No rider escalation needs action", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 110)
                                .marketplaceFlatSurface()
                        } else {
                            ForEach(safety.riderEscalations) { escalation in
                                Button { selectedEscalation = escalation } label: {
                                    HStack(spacing: MarketplaceSpacing.medium) {
                                        Image(systemName: escalation.custodyStarted ? "shippingbox.fill" : "motorcycle")
                                            .font(.title2).foregroundStyle(MarketplaceColors.warning.color)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(escalation.displayOrderNumber).font(.headline)
                                            Text(escalation.escalationState.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.subheadline).foregroundStyle(.secondary)
                                            Text(escalation.custodyStarted ? "Package custody started · recovery required" : "No custody · safe rematch available")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                    }
                                    .padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
                                }
                                .buttonStyle(.plain)
                                .disabled(!safety.permissions.canManageRiderEscalations)
                            }
                        }
                    }
                }

                Text("Every pause, resume, release and recovery action is version-checked, idempotent and written to the Admin audit trail.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(MarketplaceSpacing.large)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Safety & health")
        .refreshable { await model.refresh([.systemHealth, .operationalSafety, .commandCenter]) }
        .marketplacePage()
        .sheet(isPresented: $createsPause) {
            AdminPauseSheet(model: model, pause: nil)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $resumedPause) { pause in
            AdminPauseSheet(model: model, pause: pause)
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedEscalation) { escalation in
            AdminEscalationSheet(model: model, escalation: escalation)
                .presentationDetents([.medium])
        }
    }

    private func governanceSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
            Text(title).font(.caption.bold()).tracking(1.2).foregroundStyle(MarketplaceColors.dastakAccent.color)
            content()
        }
    }

    @ViewBuilder
    private func workspaceIssue(_ workspace: DastakAdminWorkspace) -> some View {
        if let issue = model.issue(for: workspace) {
            DastakAdminWorkspaceIssueCard(
                issue: issue,
                lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: workspace),
                isRefreshing: model.isRefreshing
            ) { Task { await model.retry(workspace) } }
        }
    }
}

private struct DastakAdminFinanceView: View {
    @ObservedObject var model: DastakOwnerOperationsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                AdminPageIntro(eyebrow: "FINANCIAL OPERATIONS", title: "Collection, fee & Royalty", detail: "Doorstep collection and journal truth remain separated from provider-paid history.")
                if let issue = model.issue(for: .liveOrders) {
                    DastakAdminWorkspaceIssueCard(
                        issue: issue,
                        lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: .liveOrders),
                        isRefreshing: model.isRefreshing
                    ) { Task { await model.retry(.liveOrders) } }
                }
                if let issue = model.issue(for: .royaltyPayouts) {
                    DastakAdminWorkspaceIssueCard(
                        issue: issue,
                        lastSuccessfulRefresh: model.lastSuccessfulRefresh(for: .royaltyPayouts),
                        isRefreshing: model.isRefreshing
                    ) { Task { await model.retry(.royaltyPayouts) } }
                }
                if let launch = model.v1Trace?.launchPayment {
                    AdminStateCard(title: "Collection \(launch.collectionStatus.replacingOccurrences(of: "_", with: " ").capitalized)", detail: "\(launch.attempts.count) recorded collection attempts", symbol: "indianrupeesign.circle", attention: launch.collectionStatus != "COLLECTED")
                    if let fee = launch.platformFee {
                        AdminStateCard(title: "Platform fee \(DastakFormatting.money(Money(paise: fee.amountPaise)))", detail: fee.balanced ? "Balanced append-only journal" : "Journal requires review", symbol: fee.balanced ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", attention: !fee.balanced)
                    } else {
                        AdminStateCard(title: "Platform fee not recognized", detail: "The 2% fee posts exactly once after successful doorstep collection.", symbol: "clock", attention: false)
                    }
                } else {
                    ContentUnavailableView("No current financial trace", systemImage: "indianrupeesign.circle", description: Text("Select a current order in Live orders first."))
                }
                Text("Merchant commission remains 0%. Merchant Royalty is created at verified handoff; Rider Royalty is created only after successful final delivery.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                    AdminSectionHeader(eyebrow: "ROYALTY PAYOUTS", title: "Withdrawal reconciliation")
                    if model.royaltyPayouts.isEmpty,
                       model.issue(for: .royaltyPayouts) == nil || model.lastSuccessfulRefresh(for: .royaltyPayouts) != nil {
                        ContentUnavailableView("No Royalty withdrawals", systemImage: "wallet.pass", description: Text("Payout requests will appear here with provider and reconciliation state."))
                            .frame(maxWidth: .infinity, minHeight: 150).marketplaceFlatSurface()
                    } else {
                        ForEach(model.royaltyPayouts) { payout in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(DastakFormatting.money(Money(paise: payout.amountPaise))).font(.title3.bold())
                                    Spacer()
                                    Text(payout.effectiveStatus.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption.bold()).foregroundStyle(MarketplaceColors.dastakAccent.color)
                                }
                                Text("\(payout.subjectType.replacingOccurrences(of: "_", with: " ").capitalized) · \(payout.destinationSnapshot.displayLabel)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                LabeledContent("Requested", value: adminDate(payout.requestedAt)).font(.caption)
                                LabeledContent("Reconciliation", value: payout.reconciliationState?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Pending provider state").font(.caption)
                                if let utr = payout.utr { LabeledContent("UTR", value: utr).font(.caption.monospaced()) }
                            }
                            .padding(MarketplaceSpacing.medium).marketplaceFlatSurface()
                        }
                    }
                }
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(MarketplaceSpacing.large)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Finance & Royalty")
        .refreshable { await model.refresh([.liveOrders, .royaltyPayouts]) }
        .marketplacePage()
    }
}

private struct AdminPauseSheet: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    let pause: DastakAdminOperationalSafety.Pause?
    @Environment(\.dismiss) private var dismiss
    @State private var scope: DastakAdminOperationalPauseScope
    @State private var targetID: String
    @State private var reason: String

    init(model: DastakOwnerOperationsModel, pause: DastakAdminOperationalSafety.Pause?) {
        self.model = model
        self.pause = pause
        _scope = State(initialValue: pause?.scope ?? .retailZone)
        _targetID = State(initialValue: pause?.targetID.uuidString ?? "")
        _reason = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(pause == nil ? "Pause new work" : "Resume new work") {
                    Picker("Scope", selection: $scope) {
                        ForEach(DastakAdminOperationalPauseScope.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.disabled(pause != nil)
                    TextField("Authoritative target ID", text: $targetID)
#if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
#endif
                        .disabled(pause != nil)
                    TextField("Audited Operations reason", text: $reason, axis: .vertical).lineLimit(3...6)
                }
                Section { Text(pause == nil ? "New matching or intake is blocked only for this exact scope and target." : "New work resumes; existing custody and order history stay unchanged.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(pause == nil ? "Create pause" : "Resume scope")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(pause == nil ? "Pause" : "Resume") { Task { await submit() } }.disabled(!valid || model.isBusy) }
            }
        }
    }

    private var valid: Bool { UUID(uuidString: targetID) != nil && reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }
    private func submit() async {
        guard let target = UUID(uuidString: targetID) else { return }
        if await model.setOperationalPause(scope: scope, targetID: target, active: pause == nil, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), expectedVersion: pause?.version ?? 0) { dismiss() }
    }
}

private struct AdminEscalationSheet: View {
    @ObservedObject var model: DastakOwnerOperationsModel
    let escalation: DastakAdminOperationalSafety.RiderEscalation
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""

    private var action: String { escalation.custodyStarted ? "ENTER_DELIVERY_RECOVERY" : "RELEASE_REMATCH" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Order \(escalation.displayOrderNumber)") {
                    LabeledContent("Escalation", value: escalation.escalationState.replacingOccurrences(of: "_", with: " ").capitalized)
                    LabeledContent("Custody", value: escalation.custodyStarted ? "Started" : "Not started")
                    TextField("Audited Operations reason", text: $reason, axis: .vertical).lineLimit(3...6)
                }
                Section { Text(escalation.custodyStarted ? "Packages stay in custody while delivery recovery begins." : "The current rider is released and safe matching restarts.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(escalation.custodyStarted ? "Start recovery" : "Release & rematch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Confirm") { Task { await submit() } }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || model.isBusy) }
            }
        }
    }

    private func submit() async {
        if await model.manageRiderEscalation(escalation, action: action, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
    }
}

private enum AdminReviewTarget: Identifiable {
    case merchant(MerchantApplication)
    case delivery(DeliveryPartnerApplication)
    var id: UUID { switch self { case let .merchant(value): value.applicationID; case let .delivery(value): value.applicationID } }
}

private struct AdminReviewSheet: View {
    let target: AdminReviewTarget
    @ObservedObject var model: DastakOwnerOperationsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reason = ""
    @State private var rejecting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                    AdminPageIntro(eyebrow: "APPLICATION REVIEW", title: title, detail: detail)
                    applicationFacts
                    Label(approvalEffect, systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(MarketplaceSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .marketplaceFlatSurface()
                    Label("Evidence is stored privately and review actions are written to the immutable audit trail.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: MarketplaceSpacing.compact) {
                        Text("PRIVATE EVIDENCE").font(.caption.bold()).tracking(1.1).foregroundStyle(MarketplaceColors.dastakAccent.color)
                        ForEach(evidence, id: \.path) { document in
                            Button {
                                Task {
                                    if let url = await model.evidenceURL(objectPath: document.path) {
                                        openURL(url)
                                    }
                                }
                            } label: {
                                HStack {
                                    Label(document.label, systemImage: "doc.text.magnifyingglass")
                                    Spacer(); Image(systemName: "arrow.up.right")
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isBusy)
                        }
                    }
                    if rejecting {
                        TextField("Reason for rejection", text: $reason, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Button(rejecting ? "Confirm rejection" : "Reject", role: .destructive) {
                            if rejecting { Task { await submit(approve: false) } } else { rejecting = true }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy || (rejecting && reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3))
                        Spacer()
                        Button("Approve") { Task { await submit(approve: true) } }
                            .buttonStyle(.borderedProminent)
                            .tint(MarketplaceColors.dastakAccent.color)
                            .disabled(model.isBusy)
                    }
                }
                .padding(MarketplaceSpacing.large)
            }
            .navigationTitle("Review")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .marketplacePage()
    }

    private var title: String { switch target { case let .merchant(value): value.businessName; case let .delivery(value): value.displayName } }
    private var detail: String { switch target { case let .merchant(value): value.businessAddress; case let .delivery(value): "\(value.deliveryMethod.displayName) · \(value.phoneNumber)" } }
    @ViewBuilder private var applicationFacts: some View {
        VStack(spacing: 0) {
            switch target {
            case let .merchant(value):
                reviewFact("Business type", value.merchantType.displayName)
                reviewFact("Legal name", value.legalName)
                reviewFact("Applicant", value.applicantName)
                reviewFact("Phone", value.applicantPhone)
                reviewFact("Service zone", value.serviceZoneName)
                reviewFact("Submitted", adminDate(value.submittedAt))
                Button {
                    if let url = merchantMapURL(value) { openURL(url) }
                } label: {
                    HStack {
                        Label("Open exact store location", systemImage: "map.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .padding(.horizontal, MarketplaceSpacing.medium)
            case let .delivery(value):
                reviewFact("Applicant", value.displayName)
                reviewFact("Phone", value.phoneNumber)
                reviewFact("Delivery method", value.deliveryMethod.displayName)
                if let registration = value.vehicleRegistrationNumber { reviewFact("Registration", registration) }
                if let vehicle = value.vehicleMakeModel { reviewFact("Vehicle", vehicle) }
                reviewFact("Submitted", adminDate(value.submittedAt))
            }
        }
        .marketplaceFlatSurface()
    }
    private func reviewFact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MarketplaceSpacing.medium) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: MarketplaceSpacing.medium)
            Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, MarketplaceSpacing.medium)
        .padding(.vertical, MarketplaceSpacing.compact)
        .overlay(alignment: .bottom) { Divider() }
    }
    private var approvalEffect: String {
        switch target {
        case .merchant:
            "Approval creates the verified merchant organization, customer-facing branch, owner permissions and a safely closed operating workspace."
        case .delivery:
            "Approval creates the verified Delivery Partner profile offline. The rider chooses when to go online after opening the workspace."
        }
    }
    private func merchantMapURL(_ application: MerchantApplication) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(application.latitude),\(application.longitude)"),
            URLQueryItem(name: "q", value: application.businessName),
        ]
        return components?.url
    }
    private var evidence: [(label: String, path: String)] {
        switch target {
        case let .merchant(value):
            [("View business evidence", value.evidenceObjectPath)]
        case let .delivery(value):
            [("View identity proof", value.identityEvidenceObjectPath)] +
                (value.vehicleEvidenceObjectPath.map { [("View vehicle RC", $0)] } ?? [])
        }
    }
    private func submit(approve: Bool) async {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool
        switch target {
        case let .merchant(value): success = await model.reviewMerchant(value, approve: approve, reason: approve ? nil : normalized)
        case let .delivery(value): success = await model.reviewDelivery(value, approve: approve, reason: approve ? nil : normalized)
        }
        if success { dismiss() }
    }
}

private struct AdminSKUEditor: View {
    let sku: DastakAdminCatalogueSKU
    @ObservedObject var model: DastakOwnerOperationsModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var variant: String
    @State private var packSize: String
    @State private var productDescription: String
    @State private var subcategoryID: UUID
    @State private var quantityValue: String
    @State private var quantityUnit: String
    @State private var packCount: String
    @State private var manufacturer: String
    @State private var countryOfOrigin: String
    @State private var barcode: String
    @State private var hsnCode: String
    @State private var dietType: String
    @State private var shelfLifeDays: String
    @State private var taxRate: String
    @State private var qaStatus: String
    @State private var listPrice: String
    @State private var sellingPrice: String
    @State private var status: String

    init(sku: DastakAdminCatalogueSKU, model: DastakOwnerOperationsModel) {
        self.sku = sku
        self.model = model
        _name = State(initialValue: sku.name)
        _variant = State(initialValue: sku.variant ?? "")
        _packSize = State(initialValue: sku.packSize)
        _productDescription = State(initialValue: sku.description ?? "")
        _subcategoryID = State(initialValue: sku.subcategoryID ?? UUID())
        _quantityValue = State(initialValue: sku.quantityValue.map { String($0) } ?? "")
        _quantityUnit = State(initialValue: sku.quantityUnit ?? "")
        _packCount = State(initialValue: sku.packCount.map(String.init) ?? "")
        _manufacturer = State(initialValue: sku.manufacturerName ?? "")
        _countryOfOrigin = State(initialValue: sku.countryOfOriginCode ?? "")
        _barcode = State(initialValue: sku.barcode ?? "")
        _hsnCode = State(initialValue: sku.hsnCode ?? "")
        _dietType = State(initialValue: sku.dietType ?? "")
        _shelfLifeDays = State(initialValue: sku.shelfLifeDays.map(String.init) ?? "")
        _taxRate = State(initialValue: sku.taxRateBps.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _qaStatus = State(initialValue: sku.qaStatus)
        _listPrice = State(initialValue: sku.listPricePaise.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _sellingPrice = State(initialValue: sku.sellingPricePaise.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _status = State(initialValue: sku.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { AdminSKURow(sku: sku) }
                Section("Customer-facing classification") {
                    LabeledContent("Department", value: sku.categoryTypeName ?? "Not classified")
                    LabeledContent("Category", value: sku.categoryName ?? "Not classified")
                    Picker("Subcategory", selection: $subcategoryID) {
                        ForEach(model.catalogueTaxonomy?.subcategories ?? []) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                }
                Section("Product identity") {
                    TextField("Product name", text: $name)
                    TextField("Variant", text: $variant)
                    TextField("Pack label", text: $packSize)
                    TextField("Customer description", text: $productDescription, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("SKU quantity") {
                    TextField("Quantity value", text: $quantityValue)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    TextField("Unit (g, kg, ml, l, pc)", text: $quantityUnit)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                    TextField("Items in pack", text: $packCount)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    Text("The pack label remains customer-facing; these fields keep quantity searchable and machine-readable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Product details") {
                    TextField("Manufacturer", text: $manufacturer)
                    TextField("Country code", text: $countryOfOrigin)
#if os(iOS)
                        .textInputAutocapitalization(.characters)
#endif
                    TextField("Barcode", text: $barcode)
#if os(iOS)
                        .textContentType(.none)
#endif
                    TextField("HSN", text: $hsnCode)
                    TextField("Diet type", text: $dietType)
                    TextField("Shelf life in days", text: $shelfLifeDays)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }
                Section("Authoritative pricing") {
                    TextField("MRP", text: $listPrice)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    TextField("Selling price", text: $sellingPrice)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    TextField("Tax %", text: $taxRate)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    if sku.listPricePaise == nil || sku.sellingPricePaise == nil {
                        Text("Pricing has not been set for this Draft SKU. Enter both amounts before saving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Visibility", selection: $status) {
                        Text("Draft").tag("DRAFT")
                        Text("Active").tag("ACTIVE").disabled(!sku.activationReady && sku.status != "ACTIVE")
                        Text("Inactive").tag("INACTIVE")
                    }
                    Picker("Quality review", selection: $qaStatus) {
                        Text("Draft").tag("DRAFT")
                        Text("In review").tag("IN_REVIEW")
                        Text("Verified").tag("VERIFIED")
                        Text("Rejected").tag("REJECTED")
                    }
                }
                Section("Activation readiness") {
                    LabeledContent("Result", value: sku.activationReady ? "Ready to activate" : "Needs attention")
                    LabeledContent("QA", value: sku.qaStatus.replacingOccurrences(of: "_", with: " ").capitalized)
                    LabeledContent("Images", value: "\(sku.imageCount)")
                    LabeledContent("Merchant selections", value: "\(sku.selectionCount ?? 0)")
                    LabeledContent("Identifiers", value: "\(sku.identifierCount)")
                    LabeledContent("Search aliases", value: "\(sku.aliasCount)")
                    if let primaryImage = sku.primaryImage {
                        LabeledContent("Image rights", value: primaryImage.rightsStatus.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                    if !sku.activationReady {
                        ForEach(sku.activationBlockers, id: \.self) { blocker in
                            Label(activationBlockerLabel(blocker), systemImage: "exclamationmark.circle")
                                .foregroundStyle(MarketplaceColors.warning.color)
                        }
                    }
                }
            }
            .navigationTitle("Edit SKU")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!canSave || model.isBusy) }
            }
        }
    }

    private var values: (Int, Int)? {
        guard let list = Decimal(string: listPrice), let selling = Decimal(string: sellingPrice) else { return nil }
        return (NSDecimalNumber(decimal: list * 100).intValue, NSDecimalNumber(decimal: selling * 100).intValue)
    }
    private var parsedQuantity: Double? { quantityValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Double(quantityValue) }
    private var parsedPackCount: Int? { packCount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Int(packCount) }
    private var parsedShelfLife: Int? { shelfLifeDays.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Int(shelfLifeDays) }
    private var parsedTaxRateBps: Int? {
        guard !taxRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let value = Decimal(string: taxRate)
        else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
    private var valid: Bool {
        guard let values, sku.subcategoryID != nil,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !packSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              values.0 >= 0, values.1 >= 0, values.1 <= values.0
        else { return false }
        if !quantityValue.isEmpty, (parsedQuantity ?? 0) <= 0 { return false }
        if !packCount.isEmpty, (parsedPackCount ?? 0) <= 0 { return false }
        if !shelfLifeDays.isEmpty, (parsedShelfLife ?? 0) <= 0 { return false }
        if !taxRate.isEmpty, !(0...10_000).contains(parsedTaxRateBps ?? -1) { return false }
        return quantityValue.isEmpty == quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canSave: Bool { valid && !(status == "ACTIVE" && sku.status != "ACTIVE" && !sku.activationReady) }
    private func save() async {
        guard let values, let originalSubcategoryID = sku.subcategoryID else { return }
        let patch = DastakAdminCatalogueSKUPatch(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            variant: optional(variant),
            packSize: packSize.trimmingCharacters(in: .whitespacesAndNewlines),
            description: optional(productDescription),
            subcategoryID: model.catalogueTaxonomy?.subcategories.contains(where: { $0.id == subcategoryID }) == true ? subcategoryID : originalSubcategoryID,
            brandID: sku.brandID,
            barcode: optional(barcode),
            quantityValue: parsedQuantity,
            quantityUnit: optional(quantityUnit)?.lowercased(),
            packCount: parsedPackCount,
            manufacturerName: optional(manufacturer),
            countryOfOriginCode: optional(countryOfOrigin)?.uppercased(),
            hsnCode: optional(hsnCode),
            dietType: optional(dietType)?.uppercased().replacingOccurrences(of: " ", with: "_"),
            shelfLifeDays: parsedShelfLife,
            listPricePaise: values.0,
            sellingPricePaise: values.1,
            taxRateBps: parsedTaxRateBps,
            qaStatus: qaStatus,
            status: status
        )
        if await model.updateCatalogueSKU(sku, patch: patch) { dismiss() }
    }
    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AdminMetric: View {
    let title: String; let value: Int; let detail: String; let symbol: String
    var body: some View { VStack(alignment: .leading, spacing: 6) { Image(systemName: symbol).foregroundStyle(MarketplaceColors.dastakAccent.color); Text("\(value)").font(.title.bold()); Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 122, alignment: .leading).padding(MarketplaceSpacing.medium).marketplaceFlatSurface() }
}
private struct AdminQueueRow: View {
    let title: String; let count: Int; let symbol: String
    var body: some View { HStack { Image(systemName: symbol).frame(width: 28).foregroundStyle(MarketplaceColors.dastakAccent.color); Text(title).font(.subheadline.weight(.medium)); Spacer(); Text("\(count)").font(.subheadline.bold()).foregroundStyle(count > 0 ? MarketplaceColors.warning.color : .secondary) }.padding(.vertical, 11).overlay(alignment: .bottom) { Divider() } }
}
private struct FlowRow: View { let title: String; let value: Int; var body: some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text("\(value)").font(.headline) } } }
private struct AdminSectionHeader: View { let eyebrow: String; let title: String; var body: some View { VStack(alignment: .leading, spacing: 3) { Text(eyebrow).font(.caption2.bold()).tracking(1.1).foregroundStyle(MarketplaceColors.dastakAccent.color); Text(title).font(.title3.bold()) }.padding(.bottom, MarketplaceSpacing.small) } }
private struct AdminPageIntro: View { let eyebrow: String; let title: String; let detail: String; var body: some View { VStack(alignment: .leading, spacing: MarketplaceSpacing.small) { Text(eyebrow).font(.caption.bold()).tracking(1.3).foregroundStyle(MarketplaceColors.dastakAccent.color); Text(title).font(.largeTitle.bold()); Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } } }
private struct AdminApprovalRow: View { let title: String; let detail: String; let symbol: String; var body: some View { HStack(spacing: MarketplaceSpacing.medium) { Image(systemName: symbol).font(.title3).foregroundStyle(MarketplaceColors.dastakAccent.color).frame(width: 46, height: 46).background(MarketplaceColors.dastakIconBackground.color, in: RoundedRectangle(cornerRadius: 14)); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(MarketplaceSpacing.medium).marketplaceFlatSurface() } }
private struct MoreRow: View { let title: String; let detail: String; let symbol: String; var body: some View { Label { VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: symbol).foregroundStyle(MarketplaceColors.dastakAccent.color) }.padding(.vertical, 4) } }
private struct AdminStateCard: View { let title: String; let detail: String; let symbol: String; let attention: Bool; var body: some View { HStack(spacing: MarketplaceSpacing.medium) { Image(systemName: symbol).font(.title2).foregroundStyle(attention ? MarketplaceColors.warning.color : MarketplaceColors.success.color); VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }; Spacer() }.padding(MarketplaceSpacing.medium).marketplaceFlatSurface() } }
private struct AdminPersonRow: View {
    let person: DastakAdminNetworkPerson

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.title3)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 44, height: 40)
                .background(
                    MarketplaceColors.dastakIconBackground.color,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName).font(.headline)
                Text(person.email ?? person.phoneNumber).font(.caption).foregroundStyle(.secondary)
                Text(person.personas.map { $0.persona.rawValue.capitalized }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
        }
    }
}
private struct AdminPersonDetail: View { let person: DastakAdminNetworkPerson; var body: some View { List { Section("Identity") { LabeledContent("Name", value: person.displayName); LabeledContent("Email", value: person.email ?? "Not available"); LabeledContent("Phone number", value: person.phoneNumber); LabeledContent("Account", value: person.accountState.capitalized); if let role = person.adminRole { LabeledContent("Admin role", value: role.displayName) } }; Section("Customer") { LabeledContent("Orders", value: "\(person.customer.orderCount)"); LabeledContent("Active orders", value: "\(person.customer.activeOrderCount)") }; if let merchant = person.merchant { Section("Merchant") { LabeledContent("Application", value: merchant.applicationStatus.capitalized); LabeledContent("Business", value: merchant.organizationName ?? merchant.businessName); LabeledContent("Branches", value: "\(merchant.branchCount)") } }; if let delivery = person.delivery { Section("Delivery Partner") { LabeledContent("Application", value: delivery.applicationStatus.capitalized); LabeledContent("Method", value: adminDeliveryMethod(delivery.deliveryMethod)); LabeledContent("Availability", value: delivery.availability?.capitalized ?? "Not active"); LabeledContent("Active missions", value: "\(delivery.activeMissionCount)") } } }.navigationTitle(person.displayName) } }

private struct AdminCatalogueCategoryTile: View {
    let category: DastakAdminCatalogueTaxonomy.Category
    let imageKey: String?
    let previewImageKeys: [String]?

    var body: some View {
        VStack(spacing: 7) {
            DastakCategoryArtwork(
                imageKey: imageKey,
                previewImageKeys: previewImageKeys,
                fallbackSymbol: DastakCatalogueSymbol.symbol(for: category.slug)
            )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            Text(category.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
            if category.status != "ACTIVE" {
                Text("COMING SOON")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AdminCatalogueDepartmentTile: View {
    let categoryType: DastakAdminCatalogueTaxonomy.CategoryType

    var body: some View {
        VStack(spacing: 7) {
            DastakCategoryArtwork(
                imageKey: categoryType.imageKey,
                previewImageKeys: categoryType.previewImageKeys,
                fallbackSymbol: DastakCatalogueSymbol.symbol(for: categoryType.slug)
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            Text(categoryType.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
            if categoryType.status != "ACTIVE" {
                Text("COMING SOON")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AdminCatalogueNavigationGroup {
    let key: String
    let name: String
    let sortOrder: Int
    let types: [DastakAdminCatalogueTaxonomy.CategoryType]
}

private struct AdminCatalogueCollectionTile: View {
    let title: String
    let imageKey: String?
    let previewImageKeys: [String]?
    let selected: Bool

    var body: some View {
        VStack(spacing: 7) {
            DastakCategoryArtwork(
                imageKey: imageKey,
                previewImageKeys: previewImageKeys,
                fallbackSymbol: title == "All" ? "sparkles" : DastakCatalogueSymbol.symbol(for: title),
                maximumImages: 1
            )
                .frame(width: 64, height: 58)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 68)
                .frame(minHeight: 30, alignment: .top)
        }
        .padding(4)
        .background(selected ? MarketplaceColors.dastakAccentSoft.color : .clear, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct AdminCatalogueGridCard: View {
    let sku: DastakAdminCatalogueSKU

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DastakProductArtwork(
                imageKey: sku.primaryImage?.imageKey ?? sku.imageKey,
                fallbackSymbol: DastakCatalogueSymbol.symbol(
                    for: [sku.categoryTypeName, sku.categoryName, sku.subcategoryName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                )
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1.04, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Image(systemName: sku.activationReady ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                    .foregroundStyle(sku.activationReady ? MarketplaceColors.success.color : MarketplaceColors.warning.color)
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if sku.primaryImage?.imageKey == nil, sku.imageKey == nil {
                    Text("ARTWORK NEEDED")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(MarketplaceColors.warning.color)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 22)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(7)
                }
            }
            if let brand = sku.brandName {
                Text(brand.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .lineLimit(1)
            }
            Text(sku.name)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            Text([sku.variant, sku.packSize].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(priceLabel)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Spacer(minLength: 4)
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                    .frame(width: 34, height: 34)
                    .background(MarketplaceColors.dastakAccentSoft.color, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(8)
        .marketplaceFlatSurface()
        .contentShape(Rectangle())
    }

    private var priceLabel: String {
        guard let sellingPricePaise = sku.sellingPricePaise else { return "Price pending" }
        return DastakFormatting.money(Money(paise: sellingPricePaise))
    }
}

private struct AdminSKUCard: View {
    let sku: DastakAdminCatalogueSKU

    var body: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.medium) {
            HStack(alignment: .top, spacing: MarketplaceSpacing.medium) {
                DastakProductArtwork(
                    imageKey: sku.primaryImage?.imageKey ?? sku.imageKey,
                    fallbackSymbol: "shippingbox"
                )
                .frame(width: 108)

                VStack(alignment: .leading, spacing: 6) {
                    Text(hierarchy)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                        .lineLimit(2)
                    Text(sku.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Text([sku.brandName, sku.variant, sku.packSize].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let description = sku.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: MarketplaceSpacing.compact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CUSTOMER PRICE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(priceLabel)
                        .font(.headline)
                }
                Spacer()
                AdminSKUStatePill(
                    title: sku.status.replacingOccurrences(of: "_", with: " ").capitalized,
                    ready: sku.status == "ACTIVE"
                )
                AdminSKUStatePill(
                    title: sku.qaStatus.replacingOccurrences(of: "_", with: " ").capitalized,
                    ready: sku.activationReady
                )
            }
        }
        .padding(MarketplaceSpacing.medium)
        .marketplaceFlatSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var hierarchy: String {
        [sku.categoryTypeName, sku.categoryName, sku.subcategoryName]
            .compactMap { $0 }
            .joined(separator: "  ›  ")
    }

    private var priceLabel: String {
        guard let sellingPricePaise = sku.sellingPricePaise else { return "Pricing not set" }
        return DastakFormatting.money(Money(paise: sellingPricePaise))
    }
}

private struct AdminSKUStatePill: View {
    let title: String
    let ready: Bool

    var body: some View {
        Label(title, systemImage: ready ? "checkmark.seal.fill" : "clock")
            .font(.caption2.weight(.bold))
            .foregroundStyle(ready ? MarketplaceColors.success.color : MarketplaceColors.warning.color)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(
                (ready ? MarketplaceColors.success.color : MarketplaceColors.warning.color).opacity(0.1),
                in: Capsule()
            )
    }
}

private struct AdminSKURow: View {
    let sku: DastakAdminCatalogueSKU

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DastakProductArtwork(
                imageKey: sku.primaryImage?.imageKey ?? sku.imageKey,
                fallbackSymbol: "shippingbox"
            )
            .frame(width: 82)
            VStack(alignment: .leading, spacing: 3) {
                Text(sku.name).font(.headline).lineLimit(2)
                Text([sku.brandName, sku.packSize].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(priceLabel) · \(sku.status.capitalized) · \(sku.qaStatus.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            Spacer()
        }
    }

    private var priceLabel: String {
        guard let sellingPricePaise = sku.sellingPricePaise else { return "Pricing not set" }
        return DastakFormatting.money(Money(paise: sellingPricePaise))
    }
}

private func adminDate(_ value: String) -> String { ISO8601DateFormatter().date(from: value)?.formatted(date: .abbreviated, time: .shortened) ?? "just now" }
private func adminDeliveryMethod(_ value: String) -> String {
    switch value.lowercased() {
    case "walking": "Walking"
    case "bicycle": "Bicycle"
    case "retired": "Retired delivery method"
    case "bike", "motorbike": "Motorbike"
    case "scooter": "Scooter"
    case "auto": "Auto"
    case "car", "goods_vehicle": "Tempo / goods vehicle"
    default: value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
private func activationBlockerLabel(_ value: String) -> String {
    [
        "QA_VERIFIED_REQUIRED": "Complete QA verification",
        "DASTAK_PRICING_REQUIRED": "Set Dastak pricing",
        "CATEGORY_TYPE_ACTIVE_REQUIRED": "Assign an active department",
        "CATEGORY_ACTIVE_REQUIRED": "Activate its category",
        "SUBCATEGORY_ACTIVE_REQUIRED": "Activate its subcategory",
        "BRAND_ACTIVE_REQUIRED": "Activate its brand",
        "SOURCE_PROVENANCE_REQUIRED": "Add source provenance",
        "PRIMARY_IMAGE_REQUIRED": "Add a primary image",
        "PRIMARY_IMAGE_VERIFICATION_REQUIRED": "Verify its primary image",
        "IMAGE_RIGHTS_CLEARANCE_REQUIRED": "Clear image usage rights",
    ][value] ?? value.replacingOccurrences(of: "_", with: " ").capitalized
}
