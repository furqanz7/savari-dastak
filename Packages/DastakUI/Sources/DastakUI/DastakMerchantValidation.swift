import Foundation
import MarketplaceInfrastructure

enum DastakMerchantValidation {
    static let packageRange = 1...1_000
    static let packageHelp = "Enter a whole number from 1 to 1,000 sealed packages."
    static let priceHelp = "Enter a price from ₹0.01 to ₹10,00,000 with at most two decimal places."
    static let extraPriceHelp = "Enter zero for a free extra, or up to ₹10,00,000 with at most two decimal places."
    static func packageCount(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil,
              let count = Int(value), packageRange.contains(count) else { return nil }
        return count
    }
    static func nameIssue(_ name: String, maximum: Int, field: String) -> String? {
        (1...maximum).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count)
            ? nil : "Enter \(field) from 1 to \(maximum) characters."
    }
    static func menuIssue(_ payload: DastakV1RestaurantMenuPayload) -> String? {
        switch payload {
        case let .category(name, description, _, _):
            return nameIssue(name, maximum: 100, field: "a category name")
                ?? (description.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 500 ? "Keep the category description within 500 characters." : nil)
        case let .item(_, name, description, _, price, _, _, _):
            return nameIssue(name, maximum: 160, field: "a dish name")
                ?? (description.unicodeScalars.count > 1_000 ? "Keep the description within 1,000 characters." : nil)
                ?? ((1...100_000_000).contains(price) ? nil : priceHelp)
        case let .optionGroup(_, name, type, minimum, maximum, _, _):
            return nameIssue(name, maximum: 100, field: "a choice name")
                ?? (!["SINGLE", "MULTIPLE"].contains(type) || minimum < 0 || maximum < 1 || maximum > Int(Int32.max)
                    || minimum > maximum || (type == "SINGLE" && maximum != 1)
                    ? "Check the choice limits. Maximum must be at least 1; a single choice allows one option." : nil)
        case let .option(_, name, price, _, _):
            return nameIssue(name, maximum: 100, field: "an option name")
                ?? ((0...100_000_000).contains(price) ? nil : extraPriceHelp)
        }
    }
}

enum DastakMerchantStoreReadError: Error {
    case wrongService, wrongLocation
    var message: String {
        switch self {
        case .wrongService: "These Store tools do not match this business type. Refresh locations and choose Grocery or Restaurant / Café as appropriate."
        case .wrongLocation: "The response belongs to a different Store location. Refresh locations, then retry the selected Store."
        }
    }
}
