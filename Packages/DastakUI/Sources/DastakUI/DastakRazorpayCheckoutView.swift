import Foundation
import MarketplaceInfrastructure
import SwiftUI

#if canImport(Razorpay) && canImport(UIKit)
import Razorpay
import UIKit

private typealias StandardRazorpayCheckout = Razorpay.RazorpayCheckout
#endif

public enum DastakRazorpayResult: Equatable, Sendable {
    case succeeded(String)
    case failed(String)
    case dismissed
}

public enum DastakPaymentMethod: String, CaseIterable, Identifiable, Sendable {
    case upiID, googlePay, paytm, phonePe, cred, pop, superMoney, jupiter, jioFinance, slice
    case card, netbanking, wallet, payLater

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .upiID: "UPI ID"
        case .googlePay: "Google Pay"
        case .paytm: "Paytm"
        case .phonePe: "PhonePe"
        case .cred: "CRED"
        case .pop: "POP"
        case .superMoney: "super.money"
        case .jupiter: "Jupiter"
        case .jioFinance: "JioFinance"
        case .slice: "slice"
        case .card: "Credit or debit card"
        case .netbanking: "Net banking"
        case .wallet: "Wallets"
        case .payLater: "Pay later"
        }
    }

    public var detail: String {
        switch self {
        case .upiID:
            "Enter a UPI ID in Razorpay"
        case .googlePay, .paytm, .phonePe, .cred, .pop, .superMoney, .jupiter, .jioFinance, .slice:
            "Razorpay opens this app when it is available"
        case .card:
            "Secure card entry and bank verification"
        case .netbanking:
            "Choose your bank securely"
        case .wallet:
            "Available wallets in Razorpay"
        case .payLater:
            "Shown when supported by your account"
        }
    }

    public var symbol: String {
        switch self {
        case .upiID, .googlePay, .paytm, .phonePe, .cred, .pop, .superMoney, .jupiter, .jioFinance, .slice:
            "arrow.up.right.circle"
        case .card:
            "creditcard"
        case .netbanking:
            "building.columns"
        case .wallet:
            "wallet.pass"
        case .payLater:
            "clock"
        }
    }

    fileprivate var razorpayMethod: String {
        switch self {
        case .card: "card"
        case .netbanking: "netbanking"
        case .wallet: "wallet"
        case .payLater: "paylater"
        case .upiID, .googlePay, .paytm, .phonePe, .cred, .pop, .superMoney, .jupiter, .jioFinance, .slice:
            "upi"
        }
    }
}

/// Hosts Razorpay's official Standard iOS Checkout. Dastak does not render the
/// provider page in its own web view: the SDK owns UPI app switching and return.
#if canImport(Razorpay) && canImport(UIKit)
public struct DastakRazorpayCheckoutView: UIViewControllerRepresentable {
    public let session: DastakCheckoutSession
    public let customerName: String?
    public let customerEmail: String?
    public let customerPhone: String?
    public let paymentMethod: DastakPaymentMethod
    public let onResult: @MainActor (DastakRazorpayResult) -> Void

    public init(
        session: DastakCheckoutSession,
        customerName: String?,
        customerEmail: String?,
        customerPhone: String?,
        paymentMethod: DastakPaymentMethod = .googlePay,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.session = session
        self.customerName = customerName
        self.customerEmail = customerEmail
        self.customerPhone = customerPhone
        self.paymentMethod = paymentMethod
        self.onResult = onResult
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    public func makeUIViewController(context: Context) -> CheckoutHostController {
        let controller = CheckoutHostController(
            session: session,
            customerName: customerName,
            customerEmail: customerEmail,
            customerPhone: customerPhone,
            paymentMethod: paymentMethod
        )
        controller.result = { result in
            Task { @MainActor in context.coordinator.onResult(result) }
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: CheckoutHostController, context: Context) {}

    @MainActor
    public final class Coordinator {
        let onResult: @MainActor (DastakRazorpayResult) -> Void

        init(onResult: @escaping @MainActor (DastakRazorpayResult) -> Void) {
            self.onResult = onResult
        }
    }

}

@MainActor
public final class CheckoutHostController: UIViewController, @preconcurrency RazorpayPaymentCompletionProtocol {
    private let session: DastakCheckoutSession
    private let customerName: String?
    private let customerEmail: String?
    private let customerPhone: String?
    private let paymentMethod: DastakPaymentMethod
    private var checkout: StandardRazorpayCheckout?
    private var hasOpenedCheckout = false
    private var completed = false
    var result: ((DastakRazorpayResult) -> Void)?

    init(
        session: DastakCheckoutSession,
        customerName: String?,
        customerEmail: String?,
        customerPhone: String?,
        paymentMethod: DastakPaymentMethod
    ) {
        self.session = session
        self.customerName = customerName
        self.customerEmail = customerEmail
        self.customerPhone = customerPhone
        self.paymentMethod = paymentMethod
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.isOpaque = true
        view.backgroundColor = UIColor(
            red: 15.0 / 255.0,
            green: 15.0 / 255.0,
            blue: 16.0 / 255.0,
            alpha: 1
        )
        modalPresentationCapturesStatusBarAppearance = true
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        openCheckoutIfNeeded()
    }

    private func openCheckoutIfNeeded() {
        guard !hasOpenedCheckout else { return }
        hasOpenedCheckout = true

        StandardRazorpayCheckout.checkIntegration(withMerchantKey: session.keyID)
        checkout = StandardRazorpayCheckout.initWithKey(session.keyID, andDelegate: self)
        checkout?.open(options, displayController: self)
    }

    private var options: [AnyHashable: Any] {
        var prefill: [String: Any] = [:]
        if let customerName, !customerName.isEmpty { prefill["name"] = customerName }
        if let customerEmail, !customerEmail.isEmpty { prefill["email"] = customerEmail }
        if let customerPhone, !customerPhone.isEmpty { prefill["contact"] = customerPhone }

        var value: [AnyHashable: Any] = [
            "key": session.keyID,
            "order_id": session.providerOrderID,
            "amount": session.amountPaise,
            "currency": session.currency,
            "name": "Dastak",
            "description": session.entityType == .parcel ? "Parcel delivery" : "Store order",
            "retry": ["enabled": true, "max_count": 4],
            "theme": ["color": "#B08D57", "backdrop_color": "#0F0F10"],
            "modal": ["confirm_close": true, "backdropclose": false, "animation": true]
        ]

        if !prefill.isEmpty { value["prefill"] = prefill }

        // Standard Checkout only supports category pre-selection. It discovers
        // installed UPI apps itself and launches the chosen app with an intent.
        if prefill["email"] != nil, prefill["contact"] != nil {
            value["method"] = paymentMethod.razorpayMethod
        }

        return value
    }

    public func onPaymentSuccess(_ paymentID: String, andData response: [AnyHashable: Any]) {
        finish(.succeeded(paymentID))
    }

    public func onPaymentSuccess(_ paymentID: String) {
        finish(.succeeded(paymentID))
    }

    public func onPaymentError(_ code: Int32, description message: String, andData response: [AnyHashable: Any]) {
        finish(.failed(Self.userFacingPaymentError(code: code, description: message)))
    }

    public func onPaymentError(_ code: Int32, description message: String) {
        finish(.failed(Self.userFacingPaymentError(code: code, description: message)))
    }

    private static func userFacingPaymentError(code: Int32, description: String) -> String {
        let normalized = description.lowercased()
        if normalized.contains("cancel") || code == 2 { return "Payment was cancelled." }
        if normalized.contains("network") || normalized.contains("timeout") {
            return "Payment could not connect. Check your internet connection and try again."
        }
        return "Payment could not be completed. Please try again or choose another payment method."
    }

    private func finish(_ value: DastakRazorpayResult) {
        guard !completed else { return }
        completed = true
        checkout = nil
        result?(value)
    }
}
#else
public struct DastakRazorpayCheckoutView: View {
    private let onResult: @MainActor (DastakRazorpayResult) -> Void

    public init(
        session: DastakCheckoutSession,
        customerName: String?,
        customerEmail: String?,
        customerPhone: String?,
        paymentMethod: DastakPaymentMethod = .googlePay,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.onResult = onResult
    }

    public var body: some View {
        Color.clear
            .task {
                onResult(.failed("Razorpay checkout is only available on iPhone and iPad."))
            }
    }
}
#endif
