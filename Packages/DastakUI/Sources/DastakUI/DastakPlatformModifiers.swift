import MarketplaceDesignSystem
import SwiftUI

private struct DastakOpaqueNavigationBar: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbarBackground(
                MarketplaceColors.canvas(for: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        content
        #endif
    }
}

extension View {
    @ViewBuilder
    func dastakFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder
    func dastakInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func dastakOpaqueNavigationBar() -> some View {
        modifier(DastakOpaqueNavigationBar())
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
    func dastakNavigationBarVisible() -> some View {
        #if os(iOS)
        toolbar(.visible, for: .navigationBar)
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
