public enum DastakApplication: String, Codable, Equatable, Sendable {
    case customerAndPartner = "dastak"
    case merchant
    case admin
}

public enum DastakAppRoot: String, Codable, Equatable, Sendable {
    case customer
    case deliveryPartner = "delivery_partner"
    case merchant
    case admin
}

public enum DeliveryPartnerAccess: String, Codable, Equatable, Sendable {
    case notApplied = "not_applied"
    case pending
    case approved
    case rejected
    case suspended
    case unavailable
}

public enum DastakAppRootError: Error, Equatable, Sendable {
    case accessDenied
}

public struct DastakAppRootState: Equatable, Sendable {
    public let application: DastakApplication
    public private(set) var activeRoot: DastakAppRoot
    public private(set) var deliveryPartnerAccess: DeliveryPartnerAccess

    public init(
        application: DastakApplication,
        deliveryPartnerAccess: DeliveryPartnerAccess = .notApplied
    ) {
        self.application = application
        self.deliveryPartnerAccess = application == .customerAndPartner
            ? deliveryPartnerAccess
            : .notApplied

        switch application {
        case .customerAndPartner:
            activeRoot = .customer
        case .merchant:
            activeRoot = .merchant
        case .admin:
            activeRoot = .admin
        }
    }

    public var availableRoots: [DastakAppRoot] {
        switch application {
        case .customerAndPartner:
            deliveryPartnerAccess == .approved
                ? [.customer, .deliveryPartner]
                : [.customer]
        case .merchant:
            [.merchant]
        case .admin:
            [.admin]
        }
    }

    public mutating func select(_ root: DastakAppRoot) throws {
        guard availableRoots.contains(root) else {
            throw DastakAppRootError.accessDenied
        }
        activeRoot = root
    }

    public mutating func updateDeliveryPartnerAccess(
        _ access: DeliveryPartnerAccess
    ) {
        guard application == .customerAndPartner else { return }

        deliveryPartnerAccess = access
        if activeRoot == .deliveryPartner, access != .approved {
            activeRoot = .customer
        }
    }
}
