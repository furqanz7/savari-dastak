//
//  LoginFlowStepContent.swift
//  Savari
//

import SwiftUI
import UIKit

struct LoginFlowStepContent: View {
    @Binding var step: LoginFlowView.LoginStep
    @Binding var role: String?
    @Binding var lastRole: String?
    @Binding var name: String
    @Binding var age: String
    @Binding var sex: String
    @Binding var phoneNumber: String
    @Binding var vehicleNumber: String
    @Binding var vehicleDocsCaptured: [UIImage]
    @Binding var driverDocsCaptured: [UIImage]
    @Binding var selfieImage: UIImage?

    let pendingAuthToken: String?
    let authToken: String?
    let onSignIn: (String) -> Void
    let onCaptureVehicle: () -> Void
    let onCaptureDriverDocs: () -> Void
    let onTakeSelfie: () -> Void
    let onPassengerComplete: () -> Void
    let onDriverComplete: () -> Void

    var body: some View {
        Group {
            switch step {
            case .roleSelection:
                RoleSelectionStep(role: $role, lastRole: $lastRole) {
                    step = .signIn
                }

            case .signIn:
                SignInStep(onSignIn: onSignIn)

            case .userInfo:
                UserInfoStep(
                    name: $name,
                    age: $age,
                    sex: $sex,
                    phoneNumber: $phoneNumber,
                    role: role ?? "Passenger",
                    userId: pendingAuthToken ?? authToken
                ) {
                    if role == "Driver" {
                        step = .driverSetup
                    } else {
                        onPassengerComplete()
                    }
                }

            case .driverSetup:
                DriverSetupStep(
                    userId: pendingAuthToken ?? authToken,
                    vehicleNumber: $vehicleNumber,
                    vehicleDocsCaptured: $vehicleDocsCaptured,
                    driverDocsCaptured: $driverDocsCaptured,
                    selfieCaptured: selfieCapturedBinding,
                    selfieImage: $selfieImage,
                    onCaptureVehicle: onCaptureVehicle,
                    captureDriverDocs: onCaptureDriverDocs,
                    takeSelfie: onTakeSelfie,
                    onComplete: onDriverComplete
                )

            case .completed:
                DashboardView(role: role ?? "Passenger")
            }
        }
    }

    private var selfieCapturedBinding: Binding<Bool> {
        Binding<Bool>(
            get: { selfieImage != nil },
            set: { newValue in
                if newValue == false {
                    selfieImage = nil
                }
            }
        )
    }
}
