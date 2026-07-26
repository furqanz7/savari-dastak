import SwiftUI

extension View {
    @ViewBuilder
    func dastakInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dastakNavigationBarHidden() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dastakPhoneKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.phonePad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dastakNumberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
