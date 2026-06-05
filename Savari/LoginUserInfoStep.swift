import SwiftUI
import Foundation
import UIKit

struct UserInfoStep: View {
    @Binding var name: String
    @Binding var age: String
    @Binding var sex: String
    @Binding var phoneNumber: String
    var role: String
    var userId: String?
    var onContinue: () -> Void

    @FocusState private var focusedField: String?

    var body: some View {
        VStack(spacing: 40) {
            header
            fields
            Spacer()
            continueButton
        }
        .background(Color.clear)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Your Details")
                .font(.system(size: 36, weight: .thin, design: .rounded))
                .foregroundColor(.primary)

            Text("Please fill in your personal information")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 40)
    }

    private var fields: some View {
        VStack(spacing: 18) {
            GlassField(placeholder: "Full Name", text: $name, focused: $focusedField, tag: "name")
            GlassField(placeholder: "Age (optional)", text: $age, focused: $focusedField, tag: "age", keyboard: .numberPad)
            GlassPicker(title: "Sex", selection: $sex, options: ["Male", "Female", "Other"])
            GlassField(placeholder: "Phone Number", text: $phoneNumber, focused: $focusedField, tag: "phone", keyboard: .phonePad)
        }
        .padding(.horizontal, 30)
        .savariCardStyle(paddingV: 16)
    }

    private var continueButton: some View {
        Button("Continue") {
            focusedField = nil
            saveProfile()
        }
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.15),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .foregroundColor(.primary)
        .cornerRadius(20)
        .shadow(color: .white.opacity(0.05), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
    }

    private func saveProfile() {
        Task.detached(priority: .userInitiated) {
            guard let token = userId, let userUUID = UUID(uuidString: token) else {
                SavariLog.debug("No Supabase user ID found")
                return
            }

            do {
                try await SupabaseManager.shared.upsertUserProfile(
                    userId: userUUID,
                    name: name,
                    phone: phoneNumber,
                    role: role,
                    age: age.isEmpty ? nil : age,
                    sex: sex.isEmpty ? nil : sex,
                    vehicleNumber: nil
                )
                await MainActor.run {
                    SavariSessionStore.setLastRole(role == "Driver" ? "Driver" : "Passenger")
                    onContinue()
                }
            } catch {
                SavariLog.debug("Failed to upsert profile:", error.localizedDescription)
            }
        }
    }
}

struct GlassField: View {
    var placeholder: String
    @Binding var text: String
    var focused: FocusState<String?>.Binding? = nil
    var tag: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        Group {
            if let focused {
                TextField(placeholder, text: $text)
                    .focused(focused, equals: tag)
                    .keyboardType(keyboard)
                    .fieldGlassStyle()
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .fieldGlassStyle()
            }
        }
    }
}

struct GlassPicker: View {
    var title: String
    @Binding var selection: String
    var options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection = option
                }
            }
        } label: {
            HStack {
                Text(selection.isEmpty ? title : selection)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
            .fieldGlassStyle()
        }
    }
}

private extension View {
    func fieldGlassStyle() -> some View {
        padding(16)
            .foregroundColor(.primary)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
            )
    }
}
