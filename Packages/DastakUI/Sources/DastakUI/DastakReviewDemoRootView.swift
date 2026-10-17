import Foundation
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI

@MainActor public enum DastakReviewDemoRouting {
  fileprivate static var handler: (() -> Void)?
  public static func openSampleUpdate() { handler?() }
}

/// Publicly discoverable demo, not a hidden review bypass. Neither this root nor
/// its local services receive an authenticated production session.
public struct DastakReviewDemoRootView: View {
  @State private var session = DastakDemoSession()
  @State private var delivery = false
  @State private var showingGuide = true
  @State private var confirmReset = false
  @State private var guideMessage: String?
  private let exit: () -> Void

  public init(exit: @escaping () -> Void) { self.exit = exit }

  public var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Label("DEMO", systemImage: "sparkles").font(.caption.bold())
        Spacer(minLength: 0)
        Button("Guide") { showingGuide = true }
        Button("Reset") { confirmReset = true }
        Button("Exit", action: exit)
      }
      .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 48)
      .background(.regularMaterial)
      Picker("Demo workspace", selection: $delivery) {
        Text("Customer").tag(false)
        Text("Delivery").tag(true)
      }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)
      ZStack {
        customer.opacity(delivery ? 0 : 1).allowsHitTesting(!delivery).accessibilityHidden(delivery)
        DastakDeliveryPartnerRootView(services: session.client.services)
          .opacity(delivery ? 1 : 0).allowsHitTesting(delivery).accessibilityHidden(!delivery)
      }.id(session.id)
    }
    .environment(\.marketplaceDemonstration, true)
    .environment(\.marketplaceSignOut, MarketplaceSignOutAction { exit() })
    .environmentObject(session.tracker)
    .environment(\.openURL, OpenURLAction { _ in .discarded })
    .sheet(isPresented: $showingGuide) { guide }
    .confirmationDialog(
      "Reset all sample work?", isPresented: $confirmReset, titleVisibility: .visible
    ) {
      Button("Reset demo", role: .destructive) {
        session.dispose()
        session = DastakDemoSession()
        delivery = false
      }
    } message: {
      Text(
        "Only this demo’s sample baskets, addresses and orders are removed. Your real account is untouched."
      )
    }
    .onAppear { DastakReviewDemoRouting.handler = { DastakAppActionInbox().request(.tracking) } }
    .onDisappear {
      DastakReviewDemoRouting.handler = nil
      session.dispose()
    }
    .onReceive(NotificationCenter.default.publisher(for: DastakAppActionInbox.opened)) { _ in
      delivery = false
      showingGuide = false
    }
    .task(id: session.id) {
      let current = session
      while !Task.isCancelled {
        if let orders = try? await current.client.customerOrders() {
          await current.system.sync(orders)
        }
        do { try await Task.sleep(for: .seconds(3)) } catch { return }
      }
    }
  }

  private var customer: some View {
    let services = session.client.services
    return DastakCustomerRootView(
      functions: services.functions,
      checkoutCustomerProvider: services.checkoutCustomer,
      accountIDProvider: services.accountID,
      issueEvidenceUploader: { _, _ in "demo/sample-evidence.jpg" },
      deliveryPartnerAccess: .approved,
      becomeDeliveryPartner: { delivery = true },
      demonstration: true, demonstrationDefaults: session.defaults)
  }

  private var guide: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          Label("A little world to explore", systemImage: "sparkles").font(.title2.bold())
          Text(
            "These are Dastak’s Customer and Delivery screens with fictional, in-memory data. Nothing is bought, dispatched, paid or uploaded."
          )
          Label("1 · Shop as a customer", systemImage: "basket").font(.headline)
          Text(
            "Pick up the basket, browse Grocery or Food, select a pack size and place a sample order. Confirm the doorstep-payment option. Your order first enters Preparing your order."
          )
          Label("2 · Simulate the kitchen or store", systemImage: "storefront").font(.headline)
          Text(
            "When ready, use the button below. It simulates merchant preparation and opens the rider-assignment stage without skipping preparation."
          )
          Button("Sample merchant: mark order ready") {
            Task {
              await session.client.advanceMerchant()
              showingGuide = false
            }
          }.buttonStyle(MarketplacePrimaryButtonStyle())
          Label("3 · Finish as a delivery partner", systemImage: "shippingbox").font(.headline)
          Text(
            "Switch to Delivery and refresh. Accept the sample offer, arrive at pickup and collect 1 package. Both sample pickup and customer PINs are 123456. Use the sample photo button, record a simulated cash collection, then complete delivery. Switch back to Customer to see the result."
          )
          Text(
            "Sample arrival checks do not use GPS. Calls, external links, real document uploads and actual payouts are unavailable. Reset starts a fresh sample session; Exit returns to normal sign-in. Demo state lasts while this session is open, including ordinary backgrounding, not after terminating the app."
          )
          .font(.footnote).foregroundStyle(.secondary)
          Label("Explore recovery and returns", systemImage: "arrow.uturn.backward.circle").font(
            .headline)
          Text(
            "After completing a sample delivery, or reporting a delivery problem after pickup, assign a sample return. Use the same 123456 PIN for customer pickup and merchant receipt. No real return or refund is created."
          )
          Button("Sample Operations: assign a return") {
            Task {
              if await session.client.assignSampleReturn() {
                delivery = true
                showingGuide = false
              } else {
                guideMessage =
                  "Complete a sample delivery, or report a delivery problem after pickup, first."
              }
            }
          }.buttonStyle(MarketplaceSecondaryButtonStyle())
          if let guideMessage { Text(guideMessage).font(.footnote).foregroundStyle(.secondary) }
          DastakDemoSystemControls(presentation: session.system)
        }.padding(24)
      }
      .navigationTitle("Demo guide").dastakInlineNavigationTitle()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Explore") { showingGuide = false } }
      }
    }
  }
}

@MainActor private final class DastakDemoSession {
  let id = UUID()
  let client = DastakReviewDemoClient()
  let defaults: UserDefaults
  let suite: String
  let tracker: DastakActiveDeliveryTracker
  let system = DastakDemoSystemPresentation()
  init() {
    suite = "com.dastak.review-demo." + id.uuidString
    defaults = UserDefaults(suiteName: suite)!
    tracker = DastakActiveDeliveryTracker(functions: client, demonstration: true)
  }
  func dispose() {
    tracker.stop()
    system.stop()
    defaults.removePersistentDomain(forName: suite)
  }
}

private struct DastakDemoSystemControls: View {
  @ObservedObject var presentation: DastakDemoSystemPresentation
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Sample system updates", systemImage: "bell.badge").font(.headline)
      Text(
        "Optionally preview local notifications and Live Activities on a supported device. These do not test remote APNs. Widgets and Shortcuts remain navigation tools, not simulated server updates."
      ).font(.footnote)
      Button("Enable local sample updates") { Task { await presentation.enable() } }
        .buttonStyle(MarketplaceSecondaryButtonStyle())
      if let message = presentation.message {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

@MainActor final class DastakDemoCheckoutStorage: DastakCheckoutJournalStorage {
  private var journal: DastakCheckoutJournal?
  func load(accountID: UUID) throws -> DastakCheckoutJournal? {
    journal?.accountID == accountID ? journal : nil
  }
  func save(_ record: DastakCheckoutJournal, replacing revision: UUID?) throws {
    guard record.isValid, journal?.revision == revision else {
      throw DastakCheckoutStorageError.changedJournal
    }
    journal = record
  }
}

actor DastakDemoDeliveryStorage: DastakDeliveryCommandStorage {
  private var command: DastakDeliveryCommand?
  func load(_ accountID: UUID) throws -> DastakDeliveryCommand? {
    command?.accountID == accountID ? command : nil
  }
  func replace(_ value: DastakDeliveryCommand?, accountID: UUID, expectedRevision: UUID?) throws {
    guard command?.revision == expectedRevision else { throw DastakDeliveryJournalError.changed }
    command = value
  }
}

actor DastakDemoPayoutStorage: DastakDeliveryPayoutStorage {
  private var command: DastakDeliveryPayoutCommand?
  func load(_ accountID: UUID) throws -> DastakDeliveryPayoutCommand? {
    command?.accountID == accountID ? command : nil
  }
  func replace(_ value: DastakDeliveryPayoutCommand?, accountID: UUID, expectedRevision: UUID?)
    throws
  {
    guard command?.revision == expectedRevision else { throw DastakDeliveryJournalError.changed }
    command = value
  }
}
