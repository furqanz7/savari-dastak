import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

/// No tokens, pickup PINs, customer destination or rider location is retained.
/// Targets, original versions, payload and upload identity are immutable.
struct DastakMerchantOperationCommand: Codable, Equatable, Sendable {
    struct Target: Codable, Equatable, Sendable {
        let id: UUID
        let orderID: UUID
        let branchID: UUID
        let version: Int
        init(_ value: DastakV1MerchantFulfilment) {
            id = value.id; orderID = value.orderID; branchID = value.branch.id; version = value.version
        }
    }
    struct Upload: Codable, Equatable, Sendable {
        let path: String
        let bucket: String
        let data: Data
        let contentType: String
        var valid: Bool {
            !data.isEmpty && data.count <= 10 * 1_024 * 1_024
                && ["image/jpeg", "image/png", "image/heic", "image/webp"].contains(contentType)
                && ["dastak-evidence", "dastak-catalogue"].contains(bucket)
                && !path.contains("..") && path.split(separator: "/").count == 3
        }
    }
    enum Operation: Codable, Equatable, Sendable {
        case retailResponse(DastakV1MerchantOpportunity, accept: Bool, minutes: Int)
        case foodResponse(DastakV1RestaurantRequest, accept: Bool, minutes: Int, reason: String?)
        case packages(Target, count: Int)
        case evidence(Target, Upload)
        case ready(Target)
        case selections(branchID: UUID, [DastakV1MerchantSelectionCommand])
        case operating(branchID: UUID, open: Bool, accepting: Bool, version: Int)
        case legacyOrder(DastakMerchantOrderAction, orderID: UUID, version: Int64, reason: String?)
        case legacyStore(name: String, address: String, location: GeoPoint, published: Bool, accepting: Bool)
        case legacyCategory(id: UUID?, name: String, sort: Int, active: Bool)
        case legacyProduct(DastakMerchantProductDraft, paise: Int, upload: Upload?)
    }
    let operation: Operation
    let key: IdempotencyKey

    var branchID: UUID? {
        switch operation {
        case let .retailResponse(item, _, _): item.branch.id
        case let .foodResponse(item, _, _, _): item.branch.id
        case let .packages(target, _), let .evidence(target, _), let .ready(target): target.branchID
        case let .selections(branchID, _), let .operating(branchID, _, _, _): branchID
        case .legacyOrder, .legacyStore, .legacyCategory, .legacyProduct: nil
        }
    }

    var upload: Upload? {
        switch operation {
        case let .evidence(_, upload), let .legacyProduct(_, _, upload?): upload
        default: nil
        }
    }
    var valid: Bool {
        guard UUID(uuidString: key.rawValue) != nil else { return false }
        switch operation {
        case let .retailResponse(item, accept, minutes):
            return (1..<Int.max).contains(item.version) && (accept ? item.prepTimeOptionsMinutes.contains(minutes) : true)
        case let .foodResponse(item, accept, minutes, reason):
            return (1..<Int.max).contains(item.version) && (accept ? (1...240).contains(minutes) : (3...500).contains(reason?.utf16.count ?? 0))
        case let .packages(target, count): return (1..<Int.max).contains(target.version) && (1...1000).contains(count)
        case let .evidence(target, upload): return (1..<Int.max).contains(target.version) && upload.valid && upload.bucket == "dastak-evidence"
        case let .ready(target): return (1..<Int.max).contains(target.version)
        case let .selections(_, values):
            return (1...1000).contains(values.count) && Set(values.map(\.skuID)).count == values.count
                && values.allSatisfy { $0.expectedVersion >= 0 && $0.expectedVersion < Int.max
                    && $0.stockQuantity.map { (0...1_000_000).contains($0) } != false }
        case let .operating(_, open, accepting, version): return (0..<Int.max).contains(version) && (open || !accepting)
        case let .legacyOrder(action, _, version, reason):
            return version >= 0 && (action != .reject || !(reason ?? "").isEmpty)
        case let .legacyStore(name, address, location, published, accepting):
            return !name.isEmpty && !address.isEmpty && location.latitude.isFinite && location.longitude.isFinite && (published || !accepting)
        case let .legacyCategory(_, name, _, _): return !name.isEmpty
        case let .legacyProduct(draft, paise, upload):
            return !draft.name.isEmpty && paise > 0 && (upload?.valid != false)
                && (upload == nil || upload?.bucket == "dastak-catalogue")
        }
    }
    var description: String {
        switch operation {
        case let .retailResponse(item, accept, _): "\(accept ? "Accept" : "Decline") request · \(item.displayOrderNumber)"
        case let .foodResponse(item, accept, _, _): "\(accept ? "Accept" : "Decline") Food order · \(item.displayOrderNumber)"
        case .packages: "Confirm package count"
        case .evidence: "Save Ready photo"
        case .ready: "Mark order Ready"
        case .selections: "Save storefront selections and stock"
        case .operating: "Update store operating state"
        case .legacyOrder: "Update earlier order"
        case .legacyStore: "Save store settings"
        case .legacyCategory: "Save category"
        case .legacyProduct: "Save product"
        }
    }
}
