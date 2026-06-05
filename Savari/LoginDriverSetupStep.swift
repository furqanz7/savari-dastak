import SwiftUI
import UIKit

struct DriverSetupStep: View {
    let userId: String?
    @Binding var vehicleNumber: String
    @Binding var vehicleDocsCaptured: [UIImage]
    @Binding var driverDocsCaptured: [UIImage]
    @Binding var selfieCaptured: Bool
    @Binding var selfieImage: UIImage?

    @State private var licenseNumber = ""

    var onCaptureVehicle: () -> Void
    var captureDriverDocs: () -> Void
    var takeSelfie: () -> Void
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            header
            uploadRequirements
            continueButton
            Spacer()
        }
        .padding(.top, 60)
        .background(Color.clear)
        .animation(.easeInOut, value: allStepsComplete)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Driver Setup")
                .font(.system(size: 34, weight: .thin, design: .rounded))
                .foregroundColor(.primary)
            Text("Complete your verification to start driving")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var uploadRequirements: some View {
        VStack(spacing: 18) {
            GlassField(placeholder: "Vehicle Number", text: $vehicleNumber, tag: "vehicle")
            GlassField(placeholder: "License Number", text: $licenseNumber, tag: "license")

            UploadCard(
                title: "Vehicle Documents",
                subtitle: vehicleDocsCaptured.isEmpty ? "Tap to upload" : "Uploaded",
                systemIcon: "car.front.fill",
                accent: .orange,
                action: onCaptureVehicle
            )
            UploadCard(
                title: "Driver License & ID",
                subtitle: driverDocsCaptured.isEmpty ? "Tap to upload" : "Uploaded",
                systemIcon: "person.badge.shield.checkmark.fill",
                accent: .green,
                action: captureDriverDocs
            )
            UploadCard(
                title: "Take Selfie",
                subtitle: selfieCaptured ? "Captured" : "Tap to open camera",
                systemIcon: "camera.aperture",
                accent: .purple,
                action: takeSelfie
            )
        }
        .padding(.horizontal, 30)
        .savariCardStyle(paddingV: 16)
    }

    @ViewBuilder
    private var continueButton: some View {
        if allStepsComplete {
            SavariButton(title: "Continue", icon: "arrow.right.circle.fill") {
                saveDriverOnboarding()
            }
            .padding(.horizontal, 40)
            .transition(.opacity.combined(with: .scale))
        }
    }

    private var allStepsComplete: Bool {
        !vehicleNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !vehicleDocsCaptured.isEmpty &&
        !driverDocsCaptured.isEmpty &&
        selfieCaptured
    }

    private func saveDriverOnboarding() {
        Task.detached(priority: .userInitiated) {
            guard let userId, let userUUID = UUID(uuidString: userId) else {
                return
            }

            do {
                let vehicleDocPaths = try await SupabaseManager.shared.uploadDriverDocuments(
                    userId: userUUID,
                    images: vehicleDocsCaptured,
                    prefix: "vehicle"
                )
                let driverDocPaths = try await SupabaseManager.shared.uploadDriverDocuments(
                    userId: userUUID,
                    images: driverDocsCaptured,
                    prefix: "driver"
                )
                var selfiePath: String?
                if let selfie = await selfieImage {
                    selfiePath = try await SupabaseManager.shared.uploadDriverDocument(
                        userId: userUUID,
                        image: selfie,
                        filename: "selfie.jpg"
                    )
                }

                try await SupabaseManager.shared.upsertDriverOnboarding(
                    profileId: userUUID,
                    vehicleNumber: vehicleNumber,
                    licenseNumber: licenseNumber,
                    vehicleDocs: vehicleDocPaths,
                    driverDocs: driverDocPaths,
                    selfiePath: selfiePath
                )

                await MainActor.run {
                    withAnimation(.spring()) {
                        onComplete()
                    }
                }
            } catch {
                SavariLog.debug("Driver onboarding upload failed:", error.localizedDescription)
            }
        }
    }
}

#if targetEnvironment(simulator)
func simulatorCaptureImage(title: String) -> UIImage {
    let size = CGSize(width: 800, height: 600)
    return UIGraphicsImageRenderer(size: size).image { context in
        UIColor.systemGray6.setFill()
        context.fill(CGRect(origin: .zero, size: size))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 52, weight: .semibold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
        let text = "\(title) capture\nSimulator smoke test"
        let rect = CGRect(x: 40, y: 235, width: size.width - 80, height: 140)
        text.draw(in: rect, withAttributes: attributes)
    }
}
#endif

struct UploadCard: View {
    let title: String
    let subtitle: String
    let systemIcon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(accent.opacity(0.25), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
    }
}
