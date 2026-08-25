import Foundation
import MarketplaceDesignSystem
import MarketplaceInfrastructure
import OSLog
import SwiftUI

public struct DastakRazorpayCompletion: Equatable, Sendable {
    public let paymentID: String
    public let orderID: String
    public let signature: String

    public init(paymentID: String, orderID: String, signature: String) {
        self.paymentID = paymentID
        self.orderID = orderID
        self.signature = signature
    }
}

public enum DastakRazorpayResult: Equatable, Sendable {
    case succeeded(DastakRazorpayCompletion)
    case failed(String)
    case dismissed
}

enum DastakPaymentCurrencyFormatter {
    static func inr(paise: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.currencyCode = "INR"
        formatter.currencySymbol = "₹"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        if let value = formatter.string(from: NSNumber(value: Double(paise) / 100)) {
            return value
        }
        return String(format: "₹%d.%02d", paise / 100, abs(paise % 100))
    }
}

public struct DastakDiscoveredUPIApp: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let packageName: String
    public let uriScheme: String?

    public init(id: String, title: String, packageName: String, uriScheme: String?) {
        self.id = id
        self.title = title
        self.packageName = packageName
        self.uriScheme = uriScheme
    }

    static func parse(_ values: [[AnyHashable: Any]]) -> [DastakDiscoveredUPIApp] {
        // Razorpay Custom Checkout 2.2 currently returns `appPackageName`
        // (for example `google_pay`, `phonepe`, or `cred`) as the value
        // expected by `upi_app_package_name`. Retain older SDK keys as
        // compatibility fallbacks.
        let packageKeys = ["appPackageName", "shortcode", "appPackage", "packageName", "upi_app_package_name", "package"]
        let titleKeys = ["appName", "displayName", "name", "title"]
        let schemeKeys = ["uriScheme", "scheme"]
        var seen = Set<String>()

        return values.compactMap { value in
            guard let package = firstString(in: value, keys: packageKeys)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !package.isEmpty,
                  seen.insert(package.lowercased()).inserted else { return nil }

            let providerTitle = firstString(in: value, keys: titleKeys)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = package
                .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
                .last
                .map { String($0).replacingOccurrences(of: "upi", with: "", options: .caseInsensitive).capitalized }
            let title = providerTitle?.isEmpty == false ? providerTitle! : (fallback?.isEmpty == false ? fallback! : "UPI app")

            return DastakDiscoveredUPIApp(
                id: package.lowercased(),
                title: title,
                packageName: package,
                uriScheme: firstString(in: value, keys: schemeKeys)
            )
        }
        .sorted { lhs, rhs in
            let left = priority(lhs)
            let right = priority(rhs)
            return left == right ? lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending : left < right
        }
    }

    private static func firstString(in value: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let result = value[key] as? String, !result.isEmpty { return result }
        }
        return nil
    }

    private static func priority(_ app: DastakDiscoveredUPIApp) -> Int {
        let value = "\(app.title) \(app.packageName)".lowercased()
        if value.contains("google") || value.contains("gpay") { return 0 }
        if value.contains("phonepe") { return 1 }
        if value.contains("cred") { return 2 }
        if value.contains("paytm") { return 3 }
        return 10
    }
}

#if canImport(Razorpay) && canImport(RazorpayCustom) && canImport(RazorpayCore) && canImport(UIKit)
import Razorpay
import RazorpayCore
import RazorpayCustom
import UIKit
import WebKit

private typealias CustomRazorpayCheckout = RazorpayCustom.RazorpayCheckout

@MainActor
private enum DastakUPIDiscovery {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dastak.app",
        category: "UPIDiscovery"
    )

    // These are query permissions only. Availability is always taken from
    // Razorpay's runtime discovery response; no app is fabricated from this list.
    static let querySchemes = [
        "tez", "phonepe", "paytmmp", "credpay", "mobikwik", "in.fampay.app",
        "bhim", "amazonpay", "navi", "kiwi", "payzapp", "jupiter", "omnicard",
        "icici", "popclubapp", "sbiyono", "myjio", "slice-upi", "bobupi",
        "shriramone", "indusmobile", "whatsapp", "whatsapp-consumer",
        "kotakbank", "freecharge", "postpe", "super", "lxme", "scapia"
    ]

    static func discover(_ completion: @escaping ([[AnyHashable: Any]]) -> Void) {
        let queryResults = querySchemes.map { scheme in
            let canOpen = URL(string: "\(scheme)://").map(UIApplication.shared.canOpenURL) ?? false
            return "\(scheme)=\(canOpen)"
        }.joined(separator: ",")

        log("provider discovery called")
        log("canOpenURL results: \(queryResults)")

        CustomRazorpayCheckout.getAppsWhichSupportUpi { values in
            Task { @MainActor in
                let rawIdentifiers = values.compactMap { value in
                    ["appPackageName", "shortcode", "appPackage", "packageName", "upi_app_package_name", "package"]
                        .compactMap { value[$0] as? String }
                        .first
                }
                let parsed = DastakDiscoveredUPIApp.parse(values)
                log("provider apps returned: raw=\(values.count), parsed=\(parsed.count)")
                log("provider identifiers returned: \(rawIdentifiers.joined(separator: ","))")
                completion(values)
            }
        }
    }

    private static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        #if DEBUG
        print("[DastakUPIDiscovery] \(message)")
        #endif
    }
}

@MainActor
private enum DastakPaymentAuthorizationState: Equatable {
    case loading
    case ready
    case launching
    case awaitingReturn
    case processing
    case failed(String)
}

@MainActor
private final class DastakCustomCheckoutController: NSObject, ObservableObject,
    @preconcurrency RazorpayPaymentCompletionProtocol, @preconcurrency WKNavigationDelegate
{
    @Published private(set) var apps: [DastakDiscoveredUPIApp] = []
    @Published private(set) var state: DastakPaymentAuthorizationState = .loading

    fileprivate let webView: WKWebView
    private let session: DastakCheckoutSession
    private let customerEmail: String?
    private let customerPhone: String?
    private let onResult: @MainActor (DastakRazorpayResult) -> Void
    private var checkout: CustomRazorpayCheckout?
    private var finished = false

    init(
        session: DastakCheckoutSession,
        customerEmail: String?,
        customerPhone: String?,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.session = session
        self.customerEmail = customerEmail
        self.customerPhone = customerPhone
        self.onResult = onResult
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        checkout = CustomRazorpayCheckout.initWithKey(
            session.keyID,
            andDelegate: self,
            withPaymentWebView: webView
        )
        DastakUPIDiscovery.logger.notice("Custom Checkout initialized before UPI discovery")
        discoverApps()
    }

    func discoverApps() {
        state = .loading
        // Use the same Custom Checkout module that performs authorization. The
        // host app grants URL-query permission; Razorpay remains the runtime
        // source of truth for which installed apps it supports.
        DastakUPIDiscovery.discover { [weak self] values in
            Task { @MainActor in
                guard let self else { return }
                self.apps = DastakDiscoveredUPIApp.parse(values)
                self.state = .ready
            }
        }
    }

    func authorize(with app: DastakDiscoveredUPIApp) {
        guard state == .ready else { return }

        let email = customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = customerPhone?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email, !email.isEmpty else {
            state = .failed("Your signed-in email is unavailable. Sign out and sign in again before payment.")
            return
        }
        guard let phone, !phone.isEmpty else {
            state = .failed("Add a delivery phone number to your Dastak profile before payment.")
            return
        }

        state = .launching
        var options: [AnyHashable: Any] = [
            "key": session.keyID,
            "order_id": session.providerOrderID,
            "amount": session.amountPaise,
            "currency": session.currency,
            "method": "upi",
            "_[flow]": "intent",
            "upi_app_package_name": app.packageName
        ]
        options["email"] = email
        options["contact"] = phone
        checkout?.authorize(options)
        state = .awaitingReturn
    }

    func cancel() {
        guard !finished else { return }
        checkout?.userCancelledPayment()
        finish(.dismissed)
    }

    func onPaymentSuccess(_ paymentID: String, andData response: [AnyHashable: Any]) {
        state = .processing
        guard let orderID = response["razorpay_order_id"] as? String,
              let signature = response["razorpay_signature"] as? String,
              orderID == session.providerOrderID,
              !paymentID.isEmpty,
              !signature.isEmpty else {
            finish(.failed("Dastak could not verify the payment return. Your payment is being reconciled securely."))
            return
        }
        finish(.succeeded(.init(paymentID: paymentID, orderID: orderID, signature: signature)))
    }

    func onPaymentSuccess(_ paymentID: String) {
        finish(.failed("Payment authorization returned without verification details. Dastak is reconciling it securely."))
    }

    func onPaymentError(_ code: Int32, description message: String, andData response: [AnyHashable: Any]) {
        finish(.failed(Self.userFacingPaymentError(code: code, description: message)))
    }

    func onPaymentError(_ code: Int32, description message: String) {
        finish(.failed(Self.userFacingPaymentError(code: code, description: message)))
    }

    private static func userFacingPaymentError(code: Int32, description: String) -> String {
        let normalized = description.lowercased()
        if normalized.contains("cancel") || code == 2 { return "Payment was cancelled. You can try again while your basket remains reserved." }
        if normalized.contains("network") || normalized.contains("timeout") {
            return "Payment could not connect. Check your internet connection and try again."
        }
        return "Payment could not be completed. Try again while your basket remains reserved."
    }

    private func finish(_ value: DastakRazorpayResult) {
        guard !finished else { return }
        finished = true
        state = .processing
        onResult(value)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        checkout?.webView(webView, didCommit: navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkout?.webView(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        checkout?.webView(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        checkout?.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let checkout else {
            decisionHandler(.allow)
            return
        }
        checkout.webView(webView, decidePolicyFor: navigationAction, handler: decisionHandler)
    }
}

public enum DastakRazorpayRedirection {
    @MainActor
    public static func handle(_ url: URL) -> Bool {
        CustomRazorpayCheckout.handleRedirection(url.absoluteString)
    }
}

public enum DastakRazorpayDiagnostics {
    /// Debug-only physical-device probe. It calls the exact discovery path used
    /// by the payment screen and emits only app identifiers/counts.
    @MainActor
    public static func runUPIDiscoveryProbe() {
        #if DEBUG
        DastakUPIDiscovery.discover { _ in }
        #endif
    }
}

private struct DastakPaymentWebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

public struct DastakRazorpayCheckoutView: View {
    private let session: DastakCheckoutSession
    @StateObject private var controller: DastakCustomCheckoutController
    @State private var selectedAppID: String?

    public init(
        session: DastakCheckoutSession,
        customerName: String?,
        customerEmail: String?,
        customerPhone: String?,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.session = session
        _ = customerName
        _controller = StateObject(wrappedValue: DastakCustomCheckoutController(
            session: session,
            customerEmail: customerEmail,
            customerPhone: customerPhone,
            onResult: onResult
        ))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    statusContent
                    if !controller.apps.isEmpty {
                        appSection(title: "Recommended", apps: Array(controller.apps.prefix(3)))
                        if controller.apps.count > 3 {
                            appSection(title: "All UPI apps", apps: controller.apps)
                        }
                    }
                    unavailableMethods
                    securityNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 124)
            }
            .background(DastakMatteBackground(style: .dark).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { paymentBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { controller.cancel() }
                        .foregroundStyle(MarketplaceColors.dastakText.color)
                }
            }
            .overlay(alignment: .topLeading) {
                DastakPaymentWebViewHost(webView: controller.webView)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: controller.apps) { _, apps in
            if selectedAppID == nil { selectedAppID = apps.first?.id }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAYMENT")
                .font(.caption.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Payment options")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(MarketplaceColors.dastakText.color)
            Text("Choose an available UPI app. Dastak never sees your UPI PIN.")
                .font(.body)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch controller.state {
        case .loading:
            statusCard(symbol: "arrow.triangle.2.circlepath", title: "Finding available UPI apps", detail: "Checking this iPhone securely.", spins: true)
        case .launching:
            statusCard(symbol: "arrow.up.right.square", title: "Opening your UPI app", detail: "Authorize there, then return to Dastak.", spins: false)
        case .awaitingReturn:
            statusCard(symbol: "iphone.and.arrow.forward", title: "Waiting for authorization", detail: "Complete payment in the selected UPI app.", spins: false)
        case .processing:
            statusCard(symbol: "checkmark.shield", title: "Confirming your payment", detail: "We're waiting for payment confirmation. This usually takes a few seconds.", spins: false)
        case let .failed(message):
            statusCard(symbol: "exclamationmark.triangle", title: "Payment needs attention", detail: message, spins: false)
        case .ready:
            if controller.apps.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard(symbol: "apps.iphone", title: "No supported UPI app found", detail: "Install a supported UPI app, then check again. Dastak will not show unavailable apps.", spins: false)
                    Button("Check again") { controller.discoverApps() }
                        .buttonStyle(MarketplaceSecondaryButtonStyle())
                }
            }
        }
    }

    private func statusCard(symbol: String, title: String, detail: String, spins: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if spins {
                    ProgressView()
                        .tint(MarketplaceColors.dastakAccent.color)
                } else {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(MarketplaceColors.dastakAccent.color)
                }
            }
            .frame(width: 42, height: 42)
            .background(MarketplaceColors.dastakAccent.color.opacity(0.12))
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(MarketplaceColors.dastakText.color)
                Text(detail).font(.footnote).foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MarketplaceColors.dastakSurface.color)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func appSection(title: String, apps: [DastakDiscoveredUPIApp]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
            VStack(spacing: 0) {
                ForEach(apps) { app in
                    Button {
                        selectedAppID = app.id
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                            Text(app.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(MarketplaceColors.dastakText.color)
                            Spacer()
                            Image(systemName: selectedAppID == app.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedAppID == app.id ? MarketplaceColors.dastakAccent.color : MarketplaceColors.dastakSecondaryText.color)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if app.id != apps.last?.id {
                        Divider().overlay(MarketplaceColors.dastakSecondaryText.color.opacity(0.16)).padding(.leading, 54)
                    }
                }
            }
            .background(MarketplaceColors.dastakSurface.color)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var unavailableMethods: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UPI FIRST")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Cards, net banking, wallets and EMI are not available in this release.")
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MarketplaceColors.dastakSurface.color.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Your total is fixed securely. Dastak never sees your UPI PIN, and your order continues only after payment is confirmed.")
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
        }
    }

    private var paymentBar: some View {
        VStack(spacing: 12) {
            Divider().overlay(MarketplaceColors.dastakSecondaryText.color.opacity(0.16))
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL").font(.caption.weight(.bold)).foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
                    Text(DastakPaymentCurrencyFormatter.inr(paise: session.amountPaise)).font(.title2.weight(.bold)).foregroundStyle(MarketplaceColors.dastakText.color)
                }
                Button("Continue") {
                    guard let app = controller.apps.first(where: { $0.id == selectedAppID }) else { return }
                    controller.authorize(with: app)
                }
                .buttonStyle(MarketplacePrimaryButtonStyle())
                .disabled(selectedAppID == nil || controller.state != .ready)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(MarketplaceColors.dastakBackground.color)
    }

}
#else
public enum DastakRazorpayRedirection {
    @MainActor public static func handle(_ url: URL) -> Bool { false }
}

public enum DastakRazorpayDiagnostics {
    @MainActor public static func runUPIDiscoveryProbe() {}
}

public struct DastakRazorpayCheckoutView: View {
    private let onResult: @MainActor (DastakRazorpayResult) -> Void

    public init(
        session: DastakCheckoutSession,
        customerName: String?,
        customerEmail: String?,
        customerPhone: String?,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.onResult = onResult
    }

    public var body: some View {
        Color.clear.task { onResult(.failed("Razorpay Custom Checkout is available only on iPhone and iPad.")) }
    }
}
#endif
