import Foundation
import MarketplaceFoundation
import MarketplaceInfrastructure

/// Retained by the Merchant workspace, never reconstructed from an edited form.
struct DastakMerchantRestaurantCommand: Codable, Equatable, Sendable {
    enum Operation: Codable, Equatable, Sendable {
        case menu(entityID: UUID?, expectedVersion: Int, payload: DastakV1RestaurantMenuPayload)
        case operating(isOpen: Bool, acceptingOrders: Bool, expectedVersion: Int)
        case media(entityType: String, entityID: UUID, expectedVersion: Int,
                   data: Data, contentType: String, fileName: String)
    }
    let branchID: UUID
    let key: IdempotencyKey
    let operation: Operation
    // Added without rewriting older journals. New creations retain their
    // target UUID before the first request, so SQL's request hash is stable.
    let creationEntityID: UUID?
    init(branchID: UUID,key: IdempotencyKey,operation: Operation) {
        self.branchID = branchID; self.key = key; self.operation = operation
        if case .menu(entityID: nil,expectedVersion: 0,payload: _) = operation { creationEntityID = UUID() }
        else { creationEntityID = nil }
    }
    var valid: Bool {
        guard UUID(uuidString: key.rawValue) != nil else { return false }
        if creationEntityID != nil {
            guard case .menu(entityID: nil,expectedVersion: 0,payload: _) = operation else { return false }
        }
        switch operation {
        case let .menu(entityID, version, _): return (0..<Int.max).contains(version) && (entityID == nil ? version == 0 : version > 0)
        case let .operating(open, accepting, version): return version > 0 && version < Int.max && (open || !accepting)
        case let .media(type, _, version, data, contentType, fileName):
            return ["RESTAURANT_BRANCH_BANNER", "RESTAURANT_MENU_ITEM"].contains(type) && (0..<Int.max).contains(version) && !data.isEmpty && data.count <= 5 * 1_024 * 1_024 && ["image/jpeg", "image/png", "image/webp"].contains(contentType) && !fileName.isEmpty && fileName.count <= 200 && fileName.unicodeScalars.allSatisfy { !CharacterSet.newlines.contains($0) }
        }
    }

    var description: String {
        switch operation {
        case let .menu(entityID, _, payload):
            "\(entityID == nil ? "Add" : "Update") \(payload.entityType.lowercased().replacingOccurrences(of: "_", with: " "))"
        case let .operating(isOpen, accepting, _):
            !isOpen ? "Close restaurant and pause new orders" : accepting ? "Open restaurant and accept new orders" : "Open restaurant with new orders paused"
        case let .media(type, _, _, _, _, _):
            type == "RESTAURANT_BRANCH_BANNER" ? "Update restaurant banner" : "Update dish photo"
        }
    }
}

extension DastakV1RestaurantMenu {
    func entityVersion(type: String, id: UUID) -> Int? {
        switch type {
        case "CATEGORY": categories.first { $0.id == id }?.version
        case "ITEM": categories.lazy.flatMap(\.items).first { $0.id == id }?.version
        case "OPTION_GROUP": categories.lazy.flatMap(\.items).flatMap(\.optionGroups).first { $0.id == id }?.version
        case "OPTION": categories.lazy.flatMap(\.items).flatMap(\.optionGroups).flatMap(\.options).first { $0.id == id }?.version
        default: nil
        }
    }
}
