import Foundation
import MarketplaceDesignSystem
import MarketplaceFoundation
import MarketplaceInfrastructure
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
private final class DastakAccountSessionsModel: ObservableObject {
    @Published private(set) var sessions: [AccountSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSigningOutOthers = false
    @Published var errorMessage: String?

    private let client: any AccountSessionClient
    private let device: AccountSessionDevice

    init(client: any AccountSessionClient, applicationName: String) {
        self.client = client
        device = Self.device(applicationName: applicationName)
    }

    var otherSessionCount: Int {
        sessions.lazy.filter { !$0.isCurrent }.count
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await client.snapshot(
                device: device,
                idempotencyKey: key()
            ).sessions
            errorMessage = nil
        } catch {
            errorMessage = "Your signed-in devices could not be loaded."
        }
    }

    func signOutOthers() async {
        guard otherSessionCount > 0 else { return }
        isSigningOutOthers = true
        defer { isSigningOutOthers = false }
        do {
            sessions = try await client.signOutOthers(
                device: device,
                idempotencyKey: key()
            ).sessions
            errorMessage = nil
        } catch {
            errorMessage = "Other devices could not be signed out."
        }
    }

    private func key() -> IdempotencyKey {
        IdempotencyKey(rawValue: UUID().uuidString)!
    }

    private static func device(applicationName: String) -> AccountSessionDevice {
        #if canImport(UIKit)
        let device = UIDevice.current
        return AccountSessionDevice(
            deviceName: device.name.isEmpty ? device.model : device.name,
            platform: "ios",
            appName: applicationName,
            userAgent: "Dastak iOS"
        )
        #else
        return AccountSessionDevice(
            deviceName: Host.current().localizedName ?? "Apple device",
            platform: "ios",
            appName: applicationName,
            userAgent: "Dastak Apple app"
        )
        #endif
    }
}

struct DastakAccountSessionsView: View {
    @StateObject private var model: DastakAccountSessionsModel

    init(client: any AccountSessionClient, applicationName: String) {
        _model = StateObject(
            wrappedValue: DastakAccountSessionsModel(
                client: client,
                applicationName: applicationName
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.large) {
                heading
                sessionContent
                securityNote
                signOutOthersButton
            }
            .frame(maxWidth: MarketplaceMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .padding(.top, MarketplaceSpacing.medium)
            .padding(.bottom, MarketplaceSpacing.xxLarge)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Devices")
        .refreshable { await model.load() }
        .task { await model.load() }
        .marketplacePage()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
            Text("ACCOUNT SECURITY")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
            Text("Devices and sessions")
                .font(MarketplaceTypography.instrumentSerif(fixedSize: 36))
            Text("Review the devices currently signed in to your Dastak account.")
                .font(MarketplaceTypography.supporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        if model.isLoading && model.sessions.isEmpty {
            HStack(spacing: MarketplaceSpacing.compact) {
                ProgressView().tint(MarketplaceColors.dastakAccent.color)
                Text("Checking signed-in devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        } else if model.sessions.isEmpty {
            VStack(alignment: .leading, spacing: MarketplaceSpacing.small) {
                Label("No sessions available", systemImage: "lock.shield")
                    .font(.headline)
                Text(model.errorMessage ?? "Pull down to check your signed-in devices again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await model.load() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MarketplaceColors.dastakAccent.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MarketplaceSpacing.medium)
            .marketplaceFlatSurface()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                    sessionRow(session)
                    if index < model.sessions.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .padding(.horizontal, MarketplaceSpacing.medium)
            .marketplaceFlatSurface()

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(MarketplaceColors.destructive.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sessionRow(_ session: AccountSession) -> some View {
        HStack(spacing: MarketplaceSpacing.compact) {
            Image(systemName: session.platform == "ios" ? "iphone" : "laptopcomputer")
                .font(.headline)
                .foregroundStyle(MarketplaceColors.dastakAccent.color)
                .frame(width: 40, height: 40)
                .background(MarketplaceColors.dastakAccentSoft.color, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(session.deviceName)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(session.appName) · \(lastSeen(session.lastSeenAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: MarketplaceSpacing.small)
            if session.isCurrent {
                Text("CURRENT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(MarketplaceColors.success.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(MarketplaceColors.success.color.opacity(0.12), in: Capsule())
            }
        }
        .frame(minHeight: 72)
        .accessibilityElement(children: .combine)
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: MarketplaceSpacing.compact) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(MarketplaceColors.success.color)
            VStack(alignment: .leading, spacing: 3) {
                Text("This device stays signed in")
                    .font(.subheadline.weight(.semibold))
                Text("Other devices may take a short moment to return to sign-in after you remove their sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signOutOthersButton: some View {
        Button {
            Task { await model.signOutOthers() }
        } label: {
            HStack {
                Image(systemName: "rectangle.stack.badge.minus")
                Text(buttonTitle)
                Spacer()
                if model.isSigningOutOthers { ProgressView() }
            }
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, MarketplaceSpacing.medium)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.otherSessionCount == 0 || model.isLoading || model.isSigningOutOthers)
        .marketplaceFlatSurface()
        .opacity(model.otherSessionCount == 0 ? 0.62 : 1)
    }

    private var buttonTitle: String {
        let count = model.otherSessionCount
        guard count > 0 else { return "No other devices" }
        return "Sign out \(count) other \(count == 1 ? "device" : "devices")"
    }

    private func lastSeen(_ value: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: value) ?? basic.date(from: value) else {
            return "Recently active"
        }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "Active now" }
        if seconds < 3_600 { return "\(max(1, Int(seconds / 60))) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) hr ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct DastakPreviewAccountSessionClient: AccountSessionClient {
    func snapshot(
        device: AccountSessionDevice,
        idempotencyKey: IdempotencyKey
    ) async throws -> AccountSessionCollection {
        AccountSessionCollection(sessions: [])
    }

    func signOutOthers(
        device: AccountSessionDevice,
        idempotencyKey: IdempotencyKey
    ) async throws -> AccountSessionCollection {
        AccountSessionCollection(sessions: [])
    }

    func endCurrent(idempotencyKey: IdempotencyKey) async throws {}
}
