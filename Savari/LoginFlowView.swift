//
//  LoginFlowView.swift
//  Savari
//

import SwiftUI
import PhotosUI
import AVFoundation
import CoreLocation
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import Supabase

struct LoginFlowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SavariDefaultsKey.lastRole) private var lastRole: String?
    @AppStorage(SavariDefaultsKey.authToken) private var authToken: String?
    @State private var pendingAuthToken: String? = nil
    @AppStorage(SavariDefaultsKey.isOnboardingComplete) private var isOnboardingComplete: Bool = false


    // MARK: - Step Flow
    @State private var step: LoginStep = .roleSelection
    
    enum LoginStep {
        case roleSelection
        case signIn
        case userInfo
        case driverSetup
        case completed
    }

    // MARK: - User Info
    @State private var role: String? = nil
    @State private var name = ""
    @State private var age = ""
    @State private var sex = ""
    @State private var phoneNumber = ""

    // MARK: - Driver Info
    @State private var vehicleNumber = ""
    @State private var vehicleDocsCaptured: [UIImage] = []
    @State private var driverDocsCaptured: [UIImage] = []
    @State private var selfieImage: UIImage? = nil

    init(role: String? = nil) {
        if SavariSessionStore.authToken != nil,
           SavariSessionStore.isOnboardingComplete {
            _step = State(initialValue: .completed)
        } else {
            _step = State(initialValue: .roleSelection)
        }
        _role = State(initialValue: role)
    }

    // MARK: - Camera / Picker
    @State private var showingPhotoPicker = false
    @State private var photoPickerFor: PhotoTarget = .none
    @State private var showingCamera = false
    @State private var showingDocCamera = false

    private let locationManager = CLLocationManager()

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.black, Color(red: 0.08, green: 0.09, blue: 0.12)]
                        : [Color.white, Color(red: 0.93, green: 0.94, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 28) {
                        Text("Savari")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        // MARK: - Step View
                        Group {
                            switch step {
                            case .roleSelection:
                                RoleSelectionStep(role: $role, lastRole: $lastRole) {
                                    step = .signIn
                                }
                                
                            case .signIn:
                                SignInStep(onSignIn: { token in
                                    pendingAuthToken = token
                                    
                                    // Reset any previous flow state to avoid auto-skipping
                                    name = ""
                                    age = ""
                                    sex = ""
                                    phoneNumber = ""
                                    
                                    vehicleNumber = ""
                                    vehicleDocsCaptured.removeAll()
                                    driverDocsCaptured.removeAll()
                                    selfieImage = nil
                                    
                                    // Always go to User Info after sign-in
                                    step = .userInfo
                                })
                                
                            case .userInfo:
                                UserInfoStep(
                                    name: $name,
                                    age: $age,
                                    sex: $sex,
                                    phoneNumber: $phoneNumber,
                                    role: role ?? "Passenger",
                                    userId: pendingAuthToken ?? authToken
                                ) {
                                    // This is now handled in UserInfoStep continue button
                                    if role == "Driver" {
                                                step = .driverSetup
                                            } else {
                                                if let pending = pendingAuthToken { authToken = pending }
                                                SavariSessionStore.setOnboardingComplete(true)
                                                step = .completed
                                            }
                                        }
                                
                            case .driverSetup:
                                let selfieCapturedBinding = Binding<Bool>(
                                    get: { selfieImage != nil },
                                    set: { newValue in
                                        if newValue == false {
                                            selfieImage = nil
                                        }
                                        // when set to true, the actual image will be provided by the camera capture handler
                                    }
                                )
                                
                                DriverSetupStep(
                                    userId: pendingAuthToken ?? authToken,
                                    vehicleNumber: $vehicleNumber,
                                    vehicleDocsCaptured: $vehicleDocsCaptured,
                                    driverDocsCaptured: $driverDocsCaptured,
                                    selfieCaptured: selfieCapturedBinding,
                                    selfieImage: $selfieImage,
                                    onCaptureVehicle: {
                                        photoPickerFor = .vehicle
                                        #if targetEnvironment(simulator)
                                        vehicleDocsCaptured.append(simulatorCaptureImage(title: "Vehicle"))
                                        #else
                                        showingDocCamera = true
                                        #endif
                                    },
                                    captureDriverDocs: {
                                        photoPickerFor = .driver
                                        #if targetEnvironment(simulator)
                                        driverDocsCaptured.append(simulatorCaptureImage(title: "Driver"))
                                        #else
                                        showingDocCamera = true
                                        #endif
                                    },
                                    takeSelfie: {
                                        #if targetEnvironment(simulator)
                                        selfieImage = simulatorCaptureImage(title: "Selfie")
                                        #else
                                        showingCamera = true
                                        #endif
                                    },
                                    onComplete: {
                                        if let pending = pendingAuthToken { authToken = pending }
                                        SavariSessionStore.setOnboardingComplete(true)
                                        step = .completed
                                    }
                                )
                                
                            case .completed:
                                DashboardView(role: role ?? "Passenger")
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    Spacer()

                    Text("© 2025 Savari")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 14)
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                silentlyRequestPermissions()
            }
        }
        // Camera / Picker overlays
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoPicker { images in
                switch photoPickerFor {
                case .vehicle: vehicleDocsCaptured.append(contentsOf: images)
                case .driver: driverDocsCaptured.append(contentsOf: images)
                case .none: break
                }
            }
        }
        .fullScreenCover(isPresented: $showingDocCamera) {
            CameraView { image in
                if let image = image {
                    switch photoPickerFor {
                    case .vehicle: vehicleDocsCaptured.append(image)
                    case .driver: driverDocsCaptured.append(image)
                    case .none: break
                    }
                }
                showingDocCamera = false
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView { image in
                if let image = image { selfieImage = image }
                showingCamera = false
            }
        }
    }

    // MARK: - Helpers
    private func silentlyRequestPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }
}
// MARK: - Sign In Step
struct SignInStep: View {
    var onSignIn: (String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // MARK: - Apple Sign-In
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                           let tokenData = appleIDCredential.identityToken,
                           let idToken = String(data: tokenData, encoding: .utf8) {
                            
                            Task(priority: TaskPriority.userInitiated) {
                                do {
                                    let user = try await SupabaseManager.shared.signInWithApple(idToken: idToken)
                                    SavariLog.debug("✅ Apple user signed in:", user.id)
                                    
                                    await MainActor.run {
                                        onSignIn(user.id.uuidString)
                                    }
                                } catch {
                                    SavariLog.debug("❌ Supabase Apple sign-in error:", error.localizedDescription)
                                }
                            }
                        }
                    case .failure(let error):
                        SavariLog.debug("Apple Sign-In failed:", error.localizedDescription)
                    }
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 55)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
            .padding(.horizontal, 15)
            
            Button(action: handleGoogleSignIn) {
                HStack {
                    Text("G").font(.headline)
                    Text("Sign in with Google").fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.93, green: 0.94, blue: 0.96))
                .cornerRadius(14)
            }
            .padding(.horizontal, 15)
        }
    }
    func handleGoogleSignIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { return }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                SavariLog.debug("❌ Google Sign-In failed:", error.localizedDescription)
                return
            }
            
            guard let idToken = result?.user.idToken?.tokenString else {
                SavariLog.debug("❌ No ID token from Google")
                return
            }
            
            Task(priority: TaskPriority.userInitiated) {
                do {
                    let user = try await SupabaseManager.shared.signInWithGoogle(idToken: idToken)
                    SavariLog.debug("✅ Supabase Google user signed in:", user.id)
                    
                    await MainActor.run {
                        onSignIn(user.id.uuidString)
                    }
                } catch {
                    SavariLog.debug("❌ Supabase Google sign-in error:", error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - RoleSelectionStep
struct RoleSelectionStep: View {
    @Binding var role: String?
    @Binding var lastRole: String?
    var onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            RoleCard(title: "Passenger", subtitle: "Find a ride nearby", icon: "figure.walk", tint: .blue) {
                role = "Passenger"
                lastRole = "Passenger"
                onContinue()
            }
            
            RoleCard(title: "Driver", subtitle: "Offer your ride", icon: "car.fill", tint: .mint) {
                role = "Driver"
                lastRole = "Driver"
                onContinue()
            }
        }
    }
}

// MARK: - UserInfoStep
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
            // Title Section
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
            
            // Form Fields
            VStack(spacing: 18) {
                GlassField(placeholder: "Full Name", text: $name, focused: $focusedField, tag: "name")
                GlassField(placeholder: "Age (optional)", text: $age, focused: $focusedField, tag: "age", keyboard: .numberPad)
                GlassPicker(title: "Sex", selection: $sex, options: ["Male", "Female", "Other"])
                GlassField(placeholder: "Phone Number", text: $phoneNumber, focused: $focusedField, tag: "phone", keyboard: .phonePad)
            }
            .padding(.horizontal, 30)
            .savariCardStyle(paddingV: 16)
            
            Spacer()
            
            Button("Continue") {
                focusedField = nil
                Task.detached(priority: TaskPriority.userInitiated) {
                    guard let token = userId, let userUUID = UUID(uuidString: token) else {
                        SavariLog.debug("⚠️ No Supabase user ID found")
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
                        SavariLog.debug("❌ Failed to upsert profile:", error.localizedDescription)
                    }
                }
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
        .background(Color.clear)
    }
}

// MARK: - GlassField
struct GlassField: View {
    var placeholder: String
    @Binding var text: String
    var focused: FocusState<String?>.Binding? = nil
    var tag: String
    var keyboard: UIKeyboardType = .default
    
    var body: some View {
        Group {
            if let focused = focused {
                TextField(placeholder, text: $text)
                    .focused(focused, equals: tag)
                    .keyboardType(keyboard)
                    .padding(16)
                    .foregroundColor(.primary)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .padding(16)
                    .foregroundColor(.primary)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
            }
        }
    }
}

// MARK: - GlassPicker
struct GlassPicker: View {
    var title: String
    @Binding var selection: String
    var options: [String]
    
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { selection = option }
            }
        } label: {
            HStack {
                Text(selection.isEmpty ? title : selection)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
            )
        }
    }
}

// MARK: - CustomTextField
struct CustomTextField: View {
    var placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        TextField(placeholder, text: $text)
            .padding()
            .keyboardType(keyboardType)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
    }
}

// MARK: - DriverSetupStep
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
            
            VStack(spacing: 18) {
                GlassField(placeholder: "Vehicle Number", text: $vehicleNumber, tag: "vehicle")
                
                GlassField(placeholder: "License Number", text: $licenseNumber, tag: "license")
                
                UploadCard(
                    title: "Vehicle Documents",
                    subtitle: vehicleDocsCaptured.isEmpty ? "Tap to upload" : "Uploaded ✓",
                    systemIcon: "car.front.fill",
                    accent: .orange,
                    action: onCaptureVehicle
                )
                UploadCard(
                    title: "Driver License & ID",
                    subtitle: driverDocsCaptured.isEmpty ? "Tap to upload" : "Uploaded ✓",
                    systemIcon: "person.badge.shield.checkmark.fill",
                    accent: .green,
                    action: captureDriverDocs
                )
                UploadCard(
                    title: "Take Selfie",
                    subtitle: selfieCaptured ? "Captured ✓" : "Tap to open camera",
                    systemIcon: "camera.aperture",
                    accent: .purple,
                    action: takeSelfie
                )
            }
            .padding(.horizontal, 30)
            .savariCardStyle(paddingV: 16)
            
            if allStepsComplete {
                SavariButton(title: "Continue", icon: "arrow.right.circle.fill") {
                    Task.detached(priority: .userInitiated) {
                        guard let userId,
                              let userUUID = UUID(uuidString: userId) else { return }

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
                            var selfiePath: String? = nil
                            if let selfie = await selfieImage {
                                selfiePath = try await SupabaseManager.shared.uploadDriverDocument(
                                    userId: userUUID,
                                    image: selfie,
                                    filename: "selfie.jpg"
                                )
                            }

                            // Save record in `driver_onboarding`
                            try await SupabaseManager.shared.upsertDriverOnboarding(
                                profileId: userUUID,
                                vehicleNumber: vehicleNumber,
                                licenseNumber: licenseNumber,
                                vehicleDocs: vehicleDocPaths,
                                driverDocs: driverDocPaths,
                                selfiePath: selfiePath
                            )

                            await MainActor.run {
                                withAnimation(.spring()) { onComplete() }
                            }
                        } catch {
                            SavariLog.debug("❌ Driver onboarding upload failed:", error.localizedDescription)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .transition(.opacity.combined(with: .scale))
            }
            
            Spacer()
        }
        .padding(.top, 60)
        .background(Color.clear)
        .animation(.easeInOut, value: allStepsComplete)
    }
    
    private var allStepsComplete: Bool {
        !vehicleNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !vehicleDocsCaptured.isEmpty &&
        !driverDocsCaptured.isEmpty &&
        selfieCaptured
    }
}

#if targetEnvironment(simulator)
private func simulatorCaptureImage(title: String) -> UIImage {
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

// MARK: - UploadCard
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

// MARK: - Utilities

enum PhotoTarget { case vehicle, driver, none }

struct PhotoPicker: UIViewControllerRepresentable {
    var onComplete: ([UIImage]) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var conf = PHPickerConfiguration(photoLibrary: .shared())
        conf.selectionLimit = 0
        conf.filter = .images
        let picker = PHPickerViewController(configuration: conf)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            var images: [UIImage] = []
            let group = DispatchGroup()
            for res in results {
                group.enter()
                res.itemProvider.loadObject(ofClass: UIImage.self) { reading, _ in
                    if let img = reading as? UIImage { images.append(img) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { self.parent.onComplete(images) }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            parent.onCapture(image)
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}

struct RoleCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground).opacity(0.06)))
        }
        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
    }
}

// MARK: - LoginFlow tweaks: contrast-friendly card container
extension View {
    /// Centers a card panel and colors text automatically using primary so it adapts to light/dark
    func savariCardStyle(paddingV: CGFloat = 20, paddingH: CGFloat = 16, cornerRadius: CGFloat = 16) -> some View {
        modifier(SavariCardStyleModifier(paddingV: paddingV, paddingH: paddingH, cornerRadius: cornerRadius))
    }
}

private struct SavariCardStyleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let paddingV: CGFloat
    let paddingH: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .padding(.horizontal, paddingH)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(cornerRadius)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                .padding(.vertical, paddingV)
        } else {
            content
                .padding(.horizontal, paddingH)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(cornerRadius)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                .padding(.vertical, paddingV)
        }
    }
}
