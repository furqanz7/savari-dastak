import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

struct DastakAdminBranchDraft {
    var displayName: String
    var line1: String
    var line2: String
    var city: String
    var state: String
    var postalCode: String
    var countryCode: String
    var latitude: String
    var longitude: String
    var serviceZoneID: UUID?
    var capacityLimit: String

    init(row: DastakAdminMerchantListing) {
        displayName = row.branch.displayName
        let address = row.branch.normalizedAddress
        line1 = address?.line1 ?? ""; line2 = address?.line2 ?? ""
        city = address?.city ?? ""; state = address?.state ?? ""
        postalCode = address?.postalCode ?? ""; countryCode = address?.countryCode ?? "IN"
        latitude = row.branch.latitude.map { String($0) } ?? ""
        longitude = row.branch.longitude.map { String($0) } ?? ""
        serviceZoneID = row.branch.serviceZone?.id
        capacityLimit = row.branch.capacityLimit.map(String.init) ?? ""
    }

    func patch(for row: DastakAdminMerchantListing, zones: [DastakAdminMerchantServiceZone]) -> DastakAdminBranchPatch? {
        func trim(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
        func optional(_ value: String) -> String? { trim(value).isEmpty ? nil : trim(value) }
        let address = DastakAdminBranchAddress(line1: trim(line1), line2: optional(line2), city: optional(city),
            state: optional(state), postalCode: optional(postalCode), countryCode: trim(countryCode).uppercased())
        guard let lat = Double(trim(latitude)), let lon = Double(trim(longitude)),
              let capacity = Int(trim(capacityLimit)), let zone = serviceZoneID,
              zones.contains(where: { $0.id == zone }),
              DastakAdminBranchPatch(displayName: trim(displayName), address: address,
                  latitude: lat, longitude: lon, capacityLimit: capacity).isValid else { return nil }
        let coordinatesChanged = lat != row.branch.latitude || lon != row.branch.longitude
        let patch = DastakAdminBranchPatch(
            displayName: trim(displayName) != row.branch.displayName ? trim(displayName) : nil,
            address: address != row.branch.normalizedAddress ? address : nil,
            latitude: coordinatesChanged ? lat : nil, longitude: coordinatesChanged ? lon : nil,
            serviceZoneId: zone != row.branch.serviceZone?.id ? zone : nil,
            capacityLimit: capacity != row.branch.capacityLimit ? capacity : nil)
        return patch.isValid ? patch : nil
    }
}

struct DastakAdminMerchantIntent: Identifiable {
    enum Kind { case status(DastakAdminMerchantTarget), correction(DastakAdminBranchPatch) }
    let row: DastakAdminMerchantListing
    let kind: Kind
    var id: UUID { row.id }
    var target: DastakAdminMerchantTarget {
        if case let .status(target) = kind { return target }; return .branch
    }
    var targetID: UUID { target == .organization ? row.organization.id : row.id }
    var expectedVersion: Int { target == .organization ? row.organization.version ?? 0 : row.branch.version }
    var currentStatus: String { target == .organization ? row.organization.status : row.branch.status }
    var resultingStatus: DastakAdminMerchantStatus { currentStatus == "SUSPENDED" ? .active : .suspended }
    var targetName: String { target == .organization ? row.organization.displayName : row.branch.displayName }
    var isCorrection: Bool { if case .correction = kind { return true }; return false }
    var title: String {
        if isCorrection { return "Apply branch corrections" }
        return "\(resultingStatus == .suspended ? "Suspend" : "Reactivate") \(target.rawValue)"
    }
    var requiresName: Bool { isCorrection || resultingStatus == .suspended }
    var blocker: String? {
        guard expectedVersion > 0, ["ACTIVE", "SUSPENDED"].contains(currentStatus) else {
            return "The record is not eligible for this action. Refresh or complete onboarding first."
        }
        if case let .correction(patch) = kind {
            guard patch.isValid else { return "Review the branch values before continuing." }
            if patch.isRouteCritical {
                guard let count = row.branch.activePickupReturnWorkCount, count >= 0 else {
                    return "Pickup/return work could not be verified. Refresh before correcting a destination."
                }
                if count > 0 { return "Active pickup or return work must finish before changing this destination." }
            }
        } else if target == .organization, resultingStatus == .suspended {
            guard let fulfilments = row.organization.activeNonTerminalFulfilmentCount, fulfilments >= 0,
                  let work = row.organization.activePickupReturnWorkCount, work >= 0 else {
                return "Active work could not be verified. Refresh before suspending the organization."
            }
            if fulfilments > 0 || work > 0 { return "Resolve active fulfilments and pickup/return work before suspending this organization." }
        }
        return nil
    }
    func canConfirm(reason: String, confirmation: String) -> Bool {
        blocker == nil && (3...500).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count) &&
            (!requiresName || confirmation == targetName)
    }
    var consequence: String {
        if case let .correction(patch) = kind {
            return patch.isRouteCritical
                ? "Pickup routing and proximity checks use these destination values. Active pickup/return work blocks this correction. Merchant type, open/closed state, pauses and history are unchanged."
                : "Only the reviewed presentation or capacity values change. Merchant type, open/closed state, pauses and history remain unchanged."
        }
        if resultingStatus == .active {
            return "Governance eligibility is restored. This does not reopen a closed store, resume an operational pause or restore a removed Customer listing."
        }
        return target == .organization
            ? "The entire organization becomes ineligible for new work. Active fulfilments and pickup/return work must be resolved first. Open/closed settings and history are preserved."
            : "This branch becomes ineligible for new work. This does not cancel existing orders, change Merchant open/closed settings, resume a pause or remove historical records."
    }
    var reviewLines: [String] {
        guard case let .correction(patch) = kind else { return ["\(currentStatus) → \(resultingStatus.rawValue)"] }
        var lines: [String] = []
        if let name = patch.displayName { lines.append("Name: \(row.branch.displayName) → \(name)") }
        if let address = patch.address { lines.append("Address: \(row.branch.normalizedAddress?.summary ?? "Unavailable") → \(address.summary)") }
        if let lat = patch.latitude, let lon = patch.longitude {
            lines.append("Coordinates: \(row.branch.latitude.map { String($0) } ?? "Unavailable"), \(row.branch.longitude.map { String($0) } ?? "Unavailable") → \(lat), \(lon)")
        }
        if let zone = patch.serviceZoneId { lines.append("Service zone: \(row.branch.serviceZone?.id?.uuidString ?? "Unavailable") → \(zone.uuidString)") }
        if let capacity = patch.capacityLimit { lines.append("Capacity: \(row.branch.capacityLimit.map(String.init) ?? "Unavailable") → \(capacity)") }
        return lines
    }
}

@MainActor
final class DastakAdminMerchantGovernanceModel: ObservableObject {
    struct Pending { let intent: DastakAdminMerchantIntent; let reason: String; let key: IdempotencyKey }
    @Published private(set) var rows: [DastakAdminMerchantListing] = []
    @Published private(set) var zones: [DastakAdminMerchantServiceZone] = []
    @Published private(set) var hasMore = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var needsRefresh = true
    @Published private(set) var pending: Pending?
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    private let client: any DastakAdminMerchantGovernanceClient
    private var cursor: DastakAdminMerchantListingCursor?
    private var query = ""
    private var generation = 0
    init(client: any DastakAdminMerchantGovernanceClient) { self.client = client }
    var canReview: Bool { !isLoading && !isSubmitting && !needsRefresh && pending == nil }

    func load(query: String = "", append: Bool = false) async {
        guard !isSubmitting, !append || (!isLoading && hasMore && !needsRefresh) else { return }
        await fetch(query: query, append: append)
    }
    private func fetch(query: String, append: Bool = false) async {
        generation += 1
        let requestGeneration = generation
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true; needsRefresh = true
        defer { if generation == requestGeneration { isLoading = false } }
        do {
            let page = try await client.merchantListingPage(query: self.query.isEmpty ? nil : self.query,
                limit: 40, cursor: append ? cursor : nil, idempotencyKey: newKey())
            guard generation == requestGeneration, !Task.isCancelled else { return }
            var merged = append ? rows : []
            for row in page.merchants {
                if let index = merged.firstIndex(where: { $0.id == row.id }) { merged[index] = row }
                else { merged.append(row) }
            }
            rows = merged; zones = page.serviceZones ?? []
            cursor = page.nextCursor; hasMore = page.hasMore && cursor != nil
            needsRefresh = false; error = nil
        } catch {
            guard generation == requestGeneration else { return }
            self.error = "Merchant records could not be refreshed. Shown data may be outdated; changes are disabled until refresh succeeds."
        }
    }
    func submit(_ intent: DastakAdminMerchantIntent, reason: String, confirmation: String) async -> Bool {
        guard canReview, intent.canConfirm(reason: reason, confirmation: confirmation),
              rows.first(where: { $0.id == intent.id }) == intent.row else { return false }
        pending = Pending(intent: intent, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), key: newKey())
        return await retryPending()
    }
    func retryPending() async -> Bool {
        guard let action = pending, !isLoading, !isSubmitting else { return false }
        isSubmitting = true; error = nil; notice = nil
        defer { isSubmitting = false }
        do {
            let intent = action.intent
            let result: DastakAdminMerchantGovernanceResult
            switch intent.kind {
            case .status:
                result = try await client.setMerchantStatus(target: intent.target, id: intent.targetID,
                    status: intent.resultingStatus, expectedVersion: intent.expectedVersion,
                    reason: action.reason, idempotencyKey: action.key)
            case let .correction(patch):
                result = try await client.correctMerchantBranch(id: intent.targetID, changes: patch,
                    expectedVersion: intent.expectedVersion, reason: action.reason, idempotencyKey: action.key)
            }
            guard result.organizationId == intent.row.organization.id,
                  (intent.target == .organization || result.branchId == intent.row.id),
                  result.version == intent.expectedVersion + 1,
                  result.status == (intent.isCorrection ? intent.currentStatus : intent.resultingStatus.rawValue),
                  !intent.isCorrection || result.changedFields?.isEmpty == false else { throw FunctionClientError.invalidResponse }
            pending = nil
            notice = "\(intent.title) accepted. Open/closed settings, operational pauses and historical records were not changed."
            await fetch(query: query)
            return true
        } catch {
            if case let FunctionClientError.api(statusCode: status, code: _, message: _) = error,
               [400, 401, 403, 404, 409, 422].contains(status) {
                pending = nil
                await fetch(query: query)
                self.error = "The server rejected this action. Review the refreshed record; active-work, permission or version safeguards may block it."
            } else {
                self.error = "The result could not be verified. Retry the reviewed action with its original request; other changes remain disabled."
            }
            return false
        }
    }
    private func newKey() -> IdempotencyKey { IdempotencyKey(rawValue: UUID().uuidString)! }
}
