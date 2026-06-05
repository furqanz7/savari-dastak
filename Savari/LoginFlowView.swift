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
