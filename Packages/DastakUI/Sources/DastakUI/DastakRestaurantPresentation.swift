import Foundation
import MarketplaceInfrastructure

enum DastakRestaurantPresentation {
    static func menuCategoryScrollTarget(
        _ categories: [DastakV1RestaurantMenuCategory], categoryID: UUID
    ) -> UUID? {
        categories.first(where: { $0.id == categoryID })?.id
    }

    /// `branchName` is the API's storefront display name, not a second public
    /// name. Match web's foodRestaurantName rule; never render both labels.
    static func customerFacingName(name: String, branchName: String) -> String {
        let storefront = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        return storefront.isEmpty ? name : storefront
    }

    static func accessibilityLabel(name: String, branchName: String, status: String) -> String {
        "\(customerFacingName(name: name, branchName: branchName)), \(status)"
    }
}
