import Foundation

public struct Money: Codable, Equatable, Hashable, Sendable {
    public let paise: Int

    public init(paise: Int) {
        self.paise = paise
    }

    public init(rupees: Decimal) {
        self.paise = NSDecimalNumber(decimal: rupees * 100).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: true,
                raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            )
        ).intValue
    }

    public var rupees: Decimal {
        Decimal(paise) / 100
    }
}
