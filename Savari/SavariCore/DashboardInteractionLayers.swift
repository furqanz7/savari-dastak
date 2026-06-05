import SwiftUI

struct DashboardInlineSearchDismissLayer: View {
    let isPresented: Bool
    let onDismiss: () -> Void

    var body: some View {
        if isPresented {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .zIndex(1)
        }
    }
}

struct DashboardManualDragLayer: View {
    @Binding var isTrackingUser: Bool

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { _ in
                        if isTrackingUser {
                            isTrackingUser = false
                        }
                    }
            )
            .allowsHitTesting(false)
    }
}

struct DashboardBottomControlsLayer: View {
    let isPassenger: Bool
    @ObservedObject var vm: DashboardViewModelRealtime
    let onGoOnline: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                if isPassenger {
                    DashboardPassengerControls(vm: vm)
                } else {
                    DriverControls(
                        isOnline: vm.isOnline,
                        onGoOnline: onGoOnline
                    )
                }
            }
            .padding()
        }
    }
}
