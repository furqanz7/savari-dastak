import Foundation

public struct Money: Codable, Equatable, Hashable, Sendable {
    public let paise: Int

    public init(paise: Int) {
        self.paise = paise
    }

    public init(rupees: Decimal) {
        let roundedPaise = NSDecimalNumber(decimal: rupees * 100).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: true,
                raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            )
        )
        let minimumPaise = NSDecimalNumber(value: Int.min)
        let maximumPaise = NSDecimalNumber(value: Int.max)
        precondition(
            roundedPaise.compare(minimumPaise) != .orderedAscending &&
                roundedPaise.compare(maximumPaise) != .orderedDescending,
            "Money amount is outside the Int paise range."
        )
        self.paise = roundedPaise.intValue
    }

    public var rupees: Decimal {
        Decimal(paise) / 100
    }
}
