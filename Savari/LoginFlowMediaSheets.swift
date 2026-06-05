//
//  LoginFlowMediaSheets.swift
//  Savari
//

import SwiftUI
import UIKit

extension View {
    func loginFlowMediaSheets(
        showingPhotoPicker: Binding<Bool>,
        photoPickerFor: Binding<PhotoTarget>,
        showingDocCamera: Binding<Bool>,
        showingCamera: Binding<Bool>,
        vehicleDocsCaptured: Binding<[UIImage]>,
        driverDocsCaptured: Binding<[UIImage]>,
        selfieImage: Binding<UIImage?>
    ) -> some View {
        modifier(
            LoginFlowMediaSheets(
                showingPhotoPicker: showingPhotoPicker,
                photoPickerFor: photoPickerFor,
                showingDocCamera: showingDocCamera,
                showingCamera: showingCamera,
                vehicleDocsCaptured: vehicleDocsCaptured,
                driverDocsCaptured: driverDocsCaptured,
                selfieImage: selfieImage
            )
        )
    }
}

private struct LoginFlowMediaSheets: ViewModifier {
    @Binding var showingPhotoPicker: Bool
    @Binding var photoPickerFor: PhotoTarget
    @Binding var showingDocCamera: Bool
    @Binding var showingCamera: Bool
    @Binding var vehicleDocsCaptured: [UIImage]
    @Binding var driverDocsCaptured: [UIImage]
    @Binding var selfieImage: UIImage?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker { images in
                    append(images: images)
                }
            }
            .fullScreenCover(isPresented: $showingDocCamera) {
                CameraView { image in
                    append(documentImage: image)
                    showingDocCamera = false
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { image in
                    selfieImage = image
                    showingCamera = false
                }
            }
    }

    private func append(images: [UIImage]) {
        switch photoPickerFor {
        case .vehicle:
            vehicleDocsCaptured.append(contentsOf: images)
        case .driver:
            driverDocsCaptured.append(contentsOf: images)
        case .none:
            break
        }
    }

    private func append(documentImage image: UIImage?) {
        guard let image else { return }

        switch photoPickerFor {
        case .vehicle:
            vehicleDocsCaptured.append(image)
        case .driver:
            driverDocsCaptured.append(image)
        case .none:
            break
        }
    }
}
