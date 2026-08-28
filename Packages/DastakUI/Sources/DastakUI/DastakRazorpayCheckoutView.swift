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
    public let providerIdentifier: String
    public let uriScheme: String?

    public init(id: String, title: String, providerIdentifier: String, uriScheme: String?) {
        self.id = id
        self.title = title
        self.providerIdentifier = providerIdentifier
        self.uriScheme = uriScheme
    }

    static func parse(_ values: [[AnyHashable: Any]]) -> [DastakDiscoveredUPIApp] {
        // Custom Checkout 2.2 returns `appPackageName` on physical devices and
        // expects that exact discovered value as `upi_app_package_name` when
        // starting Intent. Older SDK responses used the other two keys, so keep
        // them first while accepting the current SDK's runtime contract.
        let providerKeys = ["shortcode", "upi_app_package_name", "appPackageName"]
        let titleKeys = ["appName", "displayName", "name", "title"]
        let schemeKeys = ["uriScheme", "scheme"]
        var seen = Set<String>()

        return values.compactMap { value in
            guard let providerIdentifier = firstString(in: value, keys: providerKeys)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  isValidProviderIdentifier(providerIdentifier),
                  seen.insert(providerIdentifier.lowercased()).inserted else { return nil }

            let providerTitle = firstString(in: value, keys: titleKeys)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = providerIdentifier
                .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
                .last
                .map { String($0).replacingOccurrences(of: "upi", with: "", options: .caseInsensitive).capitalized }
            let title = providerTitle?.isEmpty == false ? providerTitle! : (fallback?.isEmpty == false ? fallback! : "UPI app")

            return DastakDiscoveredUPIApp(
                id: providerIdentifier.lowercased(),
                title: title,
                providerIdentifier: providerIdentifier,
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

    private static func isValidProviderIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 100 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
        }
    }

    private static func priority(_ app: DastakDiscoveredUPIApp) -> Int {
        let value = "\(app.title) \(app.providerIdentifier)".lowercased()
        if value.contains("google") || value.contains("gpay") { return 0 }
        if value.contains("phonepe") { return 1 }
        if value.contains("cred") { return 2 }
        if value.contains("paytm") { return 3 }
        return 10
    }
}

enum DastakUPIIntentRequest {
    static func options(
        providerOrderID: String,
        amountPaise: Int,
        currency: String,
        email: String,
        phone: String,
        providerIdentifier: String
    ) -> [AnyHashable: Any] {
        // The Razorpay key is supplied once when Custom Checkout is initialized.
        // Sending it again to `authorize` is rejected as `extra_field_sent`
        // before the selected UPI app can be launched.
        [
            "order_id": providerOrderID,
            "amount": amountPaise,
            "currency": currency,
            "email": email,
            "contact": phone,
            "method": "upi",
            "_[flow]": "intent",
            "upi_app_package_name": providerIdentifier
        ]
    }
}

enum DastakRazorpayRuntimePolicy {
    static func configuredMode(in bundle: Bundle = .main) -> DastakRazorpayPaymentMode? {
        guard let raw = bundle.object(forInfoDictionaryKey: "DastakRazorpayPaymentMode") as? String else {
            return nil
        }
        return DastakRazorpayPaymentMode(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
    }

    static func accepts(
        session: DastakCheckoutSession,
        configuredMode: DastakRazorpayPaymentMode?
    ) -> Bool {
        guard let configuredMode else { return false }
        return configuredMode == session.providerMode
            && ((session.providerMode == .test && session.keyID.hasPrefix("rzp_test_"))
                || (session.providerMode == .live && session.keyID.hasPrefix("rzp_live_")))
    }

    // Razorpay documents mock UPI payments in Test Mode, while UPI Intent and
    // Dynamic QR require Live Mode. Never send a Test order to a real UPI app.
    static func supportsExternalUPIIntent(_ mode: DastakRazorpayPaymentMode) -> Bool {
        mode == .live
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
private enum DastakUPIHandoffDiagnostics {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dastak.app",
        category: "UPIHandoff"
    )

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        #if DEBUG
        print("[DastakUPIHandoff] \(message)")
        appendToPhysicalDeviceProbe(message)
        #endif
    }

    #if DEBUG
    private static func appendToPhysicalDeviceProbe(_ message: String) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        let url = documents.appendingPathComponent("dastak-upi-handoff.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif

    static func logError(code: Int32, response: [AnyHashable: Any]?) {
        let source = response?["error"] as? [AnyHashable: Any] ?? response
        let fields = ["code", "source", "step", "reason"].compactMap { key -> String? in
            guard let raw = source?[key] else { return nil }
            let value = String(describing: raw)
                .replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "", options: .regularExpression)
            guard !value.isEmpty else { return nil }
            return "\(key)=\(String(value.prefix(80)))"
        }
        log("callback received category=error sdk_code=\(code) \(fields.joined(separator: " "))")
    }
}

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
                let parsed = DastakDiscoveredUPIApp.parse(values)
                log("provider apps returned: raw=\(values.count), parsed=\(parsed.count)")
                log("provider identifiers returned: \(parsed.map(\.providerIdentifier).joined(separator: ","))")
                let discoveryIdentifiers = values.compactMap { value -> String? in
                    let invocation = (value["shortcode"] as? String)
                        ?? (value["upi_app_package_name"] as? String)
                        ?? (value["appPackageName"] as? String)
                    let scheme = (value["uriScheme"] as? String)
                        ?? (value["scheme"] as? String)
                    guard invocation != nil || scheme != nil else { return nil }
                    return "invoke=\(sanitized(invocation)) scheme=\(sanitized(scheme))"
                }
                log("provider discovery mapping: \(discoveryIdentifiers.joined(separator: ";"))")
                completion(values)
            }
        }
    }

    private static func sanitized(_ value: String?) -> String {
        guard let value else { return "none" }
        let clean = value.replacingOccurrences(
            of: "[^A-Za-z0-9_.-]",
            with: "",
            options: .regularExpression
        )
        return clean.isEmpty ? "none" : String(clean.prefix(100))
    }

    private static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        #if DEBUG
        print("[DastakUPIDiscovery] \(message)")
        DastakUPIHandoffDiagnostics.log("discovery \(message)")
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
    case testModeUnavailable
    case failed(String)
}

@MainActor
private final class DastakCustomCheckoutController: NSObject, ObservableObject,
    @preconcurrency RazorpayPaymentCompletionProtocol, @preconcurrency WKNavigationDelegate,
    @preconcurrency WKUIDelegate
{
    @Published private(set) var apps: [DastakDiscoveredUPIApp] = []
    @Published private(set) var state: DastakPaymentAuthorizationState = .loading

    fileprivate let webView: WKWebView
    private let session: DastakCheckoutSession
    private let customerEmail: String?
    private let customerPhone: String?
    private let prepareTestRehearsal: @MainActor (DastakTestPaymentOutcome) async throws -> DastakTestPaymentRehearsal
    private let onResult: @MainActor (DastakRazorpayResult) -> Void
    private var checkout: CustomRazorpayCheckout?
    private var finished = false

    init(
        session: DastakCheckoutSession,
        customerEmail: String?,
        customerPhone: String?,
        prepareTestRehearsal: @escaping @MainActor (DastakTestPaymentOutcome) async throws -> DastakTestPaymentRehearsal,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.session = session
        self.customerEmail = customerEmail
        self.customerPhone = customerPhone
        self.prepareTestRehearsal = prepareTestRehearsal
        self.onResult = onResult
        webView = WKWebView(frame: UIScreen.main.bounds, configuration: WKWebViewConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        super.init()
        guard DastakRazorpayRuntimePolicy.accepts(
            session: session,
            configuredMode: DastakRazorpayRuntimePolicy.configuredMode()
        ) else {
            state = .failed("Payment configuration does not match this build. Try again after updating Dastak.")
            DastakUPIHandoffDiagnostics.log("provider mode rejected before SDK initialization")
            return
        }
        checkout = CustomRazorpayCheckout.initWithKey(
            session.keyID,
            andDelegate: self,
            withPaymentWebView: webView
        )
        // Custom Checkout configures the supplied WebView during initialization.
        // Install Dastak's forwarding delegates afterwards, matching Razorpay's
        // integration sample, so generated UPI intent URLs reach our app launcher.
        webView.navigationDelegate = self
        webView.uiDelegate = self
        DastakUPIHandoffDiagnostics.log("Custom Checkout WebView delegates installed after initialization")
        guard DastakRazorpayRuntimePolicy.supportsExternalUPIIntent(session.providerMode) else {
            state = .testModeUnavailable
            DastakUPIHandoffDiagnostics.log(
                session.testRehearsalAvailable
                    ? "TEST mode active; owner rehearsal available and external UPI Intent disabled"
                    : "TEST mode active; external UPI Intent intentionally disabled"
            )
            return
        }
        DastakUPIDiscovery.logger.notice("Custom Checkout initialized before UPI discovery")
        discoverApps()
    }

    func discoverApps() {
        guard DastakRazorpayRuntimePolicy.supportsExternalUPIIntent(session.providerMode) else {
            apps = []
            state = .testModeUnavailable
            return
        }
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
        guard DastakRazorpayRuntimePolicy.supportsExternalUPIIntent(session.providerMode) else {
            state = .testModeUnavailable
            return
        }

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

        guard let checkout else {
            state = .failed("Payment authorization is temporarily unavailable. Try again.")
            DastakUPIHandoffDiagnostics.log("SDK initiation result=checkout_unavailable")
            return
        }

        state = .launching
        DastakUPIHandoffDiagnostics.log("selected discovered provider identifier=\(app.providerIdentifier)")
        DastakUPIHandoffDiagnostics.log(
            "authorization WebView attached=\(webView.window != nil) width=\(Int(webView.bounds.width)) height=\(Int(webView.bounds.height))"
        )
        if let scheme = app.uriScheme,
           let url = URL(string: scheme),
           let schemeName = url.scheme {
            DastakUPIHandoffDiagnostics.log(
                "selected provider scheme=\(schemeName) can_open=\(UIApplication.shared.canOpenURL(url))"
            )
        }
        let options = DastakUPIIntentRequest.options(
            providerOrderID: session.providerOrderID,
            amountPaise: session.amountPaise,
            currency: session.currency,
            email: email,
            phone: phone,
            providerIdentifier: app.providerIdentifier
        )
        DastakUPIHandoffDiagnostics.log("payment initiation called flow=intent")
        checkout.authorize(options)
        DastakUPIHandoffDiagnostics.log("SDK initiation result=authorize_returned")
        if !finished, state == .launching {
            state = .awaitingReturn
        }
    }

    func authorizeTestRehearsal(_ outcome: DastakTestPaymentOutcome) {
        #if DEBUG
        guard session.providerMode == .test,
              session.testRehearsalAvailable,
              state == .testModeUnavailable else { return }

        let email = customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = customerPhone?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email, !email.isEmpty else {
            state = .failed("Your signed-in email is unavailable. Sign out and sign in again before rehearsal.")
            return
        }
        guard let phone, !phone.isEmpty else {
            state = .failed("Add a delivery phone number to your Dastak profile before rehearsal.")
            return
        }
        guard let checkout, let attemptID = session.attemptID else {
            state = .failed("Test payment rehearsal is temporarily unavailable.")
            return
        }

        state = .launching
        Task { @MainActor in
            do {
                let descriptor = try await prepareTestRehearsal(outcome)
                guard descriptor.testRehearsal,
                      descriptor.outcome == outcome,
                      descriptor.orderID == session.orderID,
                      descriptor.paymentAttemptID == attemptID,
                      descriptor.providerMode == .test,
                      descriptor.providerOrderID == session.providerOrderID,
                      descriptor.amountPaise == session.amountPaise,
                      descriptor.currency == session.currency,
                      descriptor.testVPA == (outcome == .success ? "success@razorpay" : "failure@razorpay") else {
                    state = .failed("The Test rehearsal did not match this secured payment attempt.")
                    return
                }

                DastakUPIHandoffDiagnostics.log("owner TEST rehearsal initiation outcome=\(outcome.rawValue)")
                checkout.authorize([
                    "order_id": descriptor.providerOrderID,
                    "amount": descriptor.amountPaise,
                    "currency": descriptor.currency,
                    "email": email,
                    "contact": phone,
                    "method": "upi",
                    "vpa": descriptor.testVPA
                ])
                DastakUPIHandoffDiagnostics.log("owner TEST rehearsal SDK authorize returned")
                if !finished, state == .launching { state = .awaitingReturn }
            } catch {
                state = .failed("Test payment rehearsal could not start. Try again while the basket remains reserved.")
            }
        }
        #endif
    }

    func cancel() {
        guard !finished else { return }
        checkout?.userCancelledPayment()
        finish(.dismissed)
    }

    func onPaymentSuccess(_ paymentID: String, andData response: [AnyHashable: Any]) {
        DastakUPIHandoffDiagnostics.log("callback received category=success_with_verification")
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
        DastakUPIHandoffDiagnostics.log("callback received category=success_without_verification")
        finish(.failed("Payment authorization returned without verification details. Dastak is reconciling it securely."))
    }

    func onPaymentError(_ code: Int32, description message: String, andData response: [AnyHashable: Any]) {
        DastakUPIHandoffDiagnostics.logError(code: code, response: response)
        finish(.failed(Self.userFacingPaymentError(code: code, description: message)))
    }

    func onPaymentError(_ code: Int32, description message: String) {
        DastakUPIHandoffDiagnostics.logError(code: code, response: nil)
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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logNavigation(stage: "did_start", url: webView.url)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        logNavigation(stage: "did_commit", url: webView.url)
        checkout?.webView(webView, didCommit: navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logNavigation(stage: "did_finish", url: webView.url)
        checkout?.webView(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logNavigationError(stage: "did_fail", error: error)
        checkout?.webView(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logNavigationError(stage: "did_fail_provisional", error: error)
        checkout?.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        logNavigation(
            stage: "decide_policy target_main=\(navigationAction.targetFrame?.isMainFrame == true)",
            url: navigationAction.request.url
        )
        if let scheme = navigationAction.request.url?.scheme?.lowercased(),
           !["http", "https", "about", "data", "blob"].contains(scheme) {
            // Razorpay's Custom Checkout owns the selected-provider handoff.
            // Forwarding the intent navigation lets the SDK validate and open
            // the exact app returned by discovery; opening it ourselves loses
            // Razorpay's authorization/callback state.
            DastakUPIHandoffDiagnostics.log(
                "external-app navigation delegated to Razorpay scheme=\(sanitizedURLComponent(scheme))"
            )
        }
        guard let checkout else {
            decisionHandler(.allow)
            return
        }
        checkout.webView(webView, decidePolicyFor: navigationAction, handler: decisionHandler)
    }

    private func logNavigation(stage: String, url: URL?) {
        let scheme = sanitizedURLComponent(url?.scheme)
        let host = sanitizedURLComponent(url?.host)
        DastakUPIHandoffDiagnostics.log("webview \(stage) scheme=\(scheme) host=\(host)")
    }

    private func logNavigationError(stage: String, error: Error) {
        let nsError = error as NSError
        let domain = sanitizedURLComponent(nsError.domain)
        DastakUPIHandoffDiagnostics.log("webview \(stage) domain=\(domain) code=\(nsError.code)")
    }

    private func sanitizedURLComponent(_ value: String?) -> String {
        guard let value else { return "none" }
        let clean = value.replacingOccurrences(
            of: "[^A-Za-z0-9_.-]",
            with: "",
            options: .regularExpression
        )
        return clean.isEmpty ? "none" : String(clean.prefix(100))
    }

}

public enum DastakRazorpayRedirection {
    @MainActor
    public static func handle(_ url: URL) -> Bool {
        DastakUPIHandoffDiagnostics.log("return URL received scheme=\(url.scheme ?? "unknown")")
        let handled = CustomRazorpayCheckout.handleRedirection(url.absoluteString)
        DastakUPIHandoffDiagnostics.log("return callback forwarded handled=\(handled)")
        return handled
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

    func makeUIView(context: Context) -> WKWebView {
        webView.isHidden = false
        webView.alpha = 1
        return webView
    }
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
        prepareTestRehearsal: @escaping @MainActor (DastakTestPaymentOutcome) async throws -> DastakTestPaymentRehearsal,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.session = session
        _ = customerName
        _controller = StateObject(wrappedValue: DastakCustomCheckoutController(
            session: session,
            customerEmail: customerEmail,
            customerPhone: customerPhone,
            prepareTestRehearsal: prepareTestRehearsal,
            onResult: onResult
        ))
    }

    public var body: some View {
        ZStack {
            // Razorpay Custom Checkout drives UPI Intent through the supplied
            // WKWebView. Keep it full-size and attached to the window, exactly as
            // the SDK sample does, while Dastak's opaque UI remains visually on top.
            DastakPaymentWebViewHost(webView: controller.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        statusContent
                        #if DEBUG
                        if session.providerMode == .test, session.testRehearsalAvailable {
                            testRehearsalSection
                        }
                        #endif
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
            }
            .background(DastakMatteBackground(style: .dark).ignoresSafeArea())
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
        case .testModeUnavailable:
            statusCard(
                symbol: "hammer.circle",
                title: "Test payment rehearsal",
                detail: session.testRehearsalAvailable
                    ? "Owner controls use Razorpay Test fixtures only. No real money or genuine UPI-app authorization occurs."
                    : "External UPI authorization is unavailable in this rehearsal build. Live payments remain disabled until Dastak explicitly returns to live mode.",
                spins: false
            )
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

    #if DEBUG
    private var testRehearsalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TEST PAYMENT REHEARSAL")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
                Spacer()
                Text("OWNER ONLY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
            }
            Text("Exercise the genuine Razorpay Test provider and webhook lifecycle. This does not move real money or open a real UPI app.")
                .font(.footnote)
                .foregroundStyle(MarketplaceColors.dastakSecondaryText.color)
            HStack(spacing: 12) {
                Button("Simulate success") { controller.authorizeTestRehearsal(.success) }
                    .buttonStyle(MarketplacePrimaryButtonStyle())
                Button("Simulate failure") { controller.authorizeTestRehearsal(.failure) }
                    .buttonStyle(MarketplaceSecondaryButtonStyle())
            }
            .disabled(controller.state != .testModeUnavailable)
        }
        .padding(16)
        .background(MarketplaceColors.dastakSurface.color)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    #endif

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
        prepareTestRehearsal: @escaping @MainActor (DastakTestPaymentOutcome) async throws -> DastakTestPaymentRehearsal,
        onResult: @escaping @MainActor (DastakRazorpayResult) -> Void
    ) {
        self.onResult = onResult
    }

    public var body: some View {
        Color.clear.task { onResult(.failed("Razorpay Custom Checkout is available only on iPhone and iPad.")) }
    }
}
#endif
