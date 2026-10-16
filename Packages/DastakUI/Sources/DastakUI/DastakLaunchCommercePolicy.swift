/// Customer/Delivery launch scope. Historical orders remain readable, but this
/// release must not create an online checkout or new prepaid parcel delivery.
/// The SDK-backed implementation is retained separately in the source file's
/// conditional compilation branch for a future explicitly enabled integration.
enum DastakLaunchCommercePolicy {
    static let allowsLegacyOnlineCheckout = false
    static let onlinePaymentUnavailableMessage =
        "Online payment for older orders is unavailable in this release. Contact Dastak support for help."

    static func canRetryLegacyPayment(serverAllows: Bool) -> Bool {
        allowsLegacyOnlineCheckout && serverAllows
    }
}
