//
//  LoginFlowView.swift
//  Savari
//

import SwiftUI
import CoreLocation
import UIKit

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
                        
                        LoginFlowStepContent(
                            step: $step,
                            role: $role,
                            lastRole: $lastRole,
                            name: $name,
                            age: $age,
                            sex: $sex,
                            phoneNumber: $phoneNumber,
                            vehicleNumber: $vehicleNumber,
                            vehicleDocsCaptured: $vehicleDocsCaptured,
                            driverDocsCaptured: $driverDocsCaptured,
                            selfieImage: $selfieImage,
                            pendingAuthToken: pendingAuthToken,
                            authToken: authToken,
                            onSignIn: handleSignIn,
                            onCaptureVehicle: captureVehicleDocument,
                            onCaptureDriverDocs: captureDriverDocuments,
                            onTakeSelfie: takeSelfie,
                            onPassengerComplete: completeOnboarding,
                            onDriverComplete: completeOnboarding
                        )
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
        .loginFlowMediaSheets(
            showingPhotoPicker: $showingPhotoPicker,
            photoPickerFor: $photoPickerFor,
            showingDocCamera: $showingDocCamera,
            showingCamera: $showingCamera,
            vehicleDocsCaptured: $vehicleDocsCaptured,
            driverDocsCaptured: $driverDocsCaptured,
            selfieImage: $selfieImage
        )
    }

    // MARK: - Helpers
    private func handleSignIn(token: String) {
        pendingAuthToken = token
        resetOnboardingState()
        step = .userInfo
    }

    private func resetOnboardingState() {
        name = ""
        age = ""
        sex = ""
        phoneNumber = ""
        vehicleNumber = ""
        vehicleDocsCaptured.removeAll()
        driverDocsCaptured.removeAll()
        selfieImage = nil
    }

    private func captureVehicleDocument() {
        photoPickerFor = .vehicle
        #if targetEnvironment(simulator)
        vehicleDocsCaptured.append(simulatorCaptureImage(title: "Vehicle"))
        #else
        showingDocCamera = true
        #endif
    }

    private func captureDriverDocuments() {
        photoPickerFor = .driver
        #if targetEnvironment(simulator)
        driverDocsCaptured.append(simulatorCaptureImage(title: "Driver"))
        #else
        showingDocCamera = true
        #endif
    }

    private func takeSelfie() {
        #if targetEnvironment(simulator)
        selfieImage = simulatorCaptureImage(title: "Selfie")
        #else
        showingCamera = true
        #endif
    }

    private func completeOnboarding() {
        if let pending = pendingAuthToken {
            authToken = pending
        }
        SavariSessionStore.setOnboardingComplete(true)
        step = .completed
    }

    private func silentlyRequestPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }
}
