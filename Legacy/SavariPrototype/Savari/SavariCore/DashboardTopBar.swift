import SwiftUI
import MapKit

struct DashboardTopBar: View {
    let role: String
    @ObservedObject var vm: DashboardViewModelRealtime
    @ObservedObject var inlineCompleter: LocationCompleter
    @Binding var destinationText: String
    @Binding var showingInlineSearch: Bool
    @Binding var inlineQuery: String
    @Binding var inlineChosenMapItem: MKMapItem?
    @Binding var showMapPickerSheet: Bool
    var inlineFieldIsFocused: FocusState<Bool>.Binding
    let isSigningOut: Bool
    let onSignOut: () -> Void
    let onInlineQueryChanged: (String) -> Void
    let onClearInlineQuery: () -> Void
    let onMapPickerDismiss: () -> Void
    let onMapItemPicked: (MKMapItem) -> Void
    let onCancelPassengerFlow: () -> Void
    let onCompletionSelected: (LocationCompleter.CompletionItem) -> Void

    var body: some View {
        VStack(spacing: 8) {
            DashboardTopBarHeader(
                vm: vm,
                isSigningOut: isSigningOut,
                onSignOut: onSignOut
            )

            DashboardTopBarSearchRow(
                isPassenger: isPassenger,
                vm: vm,
                inlineCompleter: inlineCompleter,
                destinationText: $destinationText,
                showingInlineSearch: $showingInlineSearch,
                inlineQuery: $inlineQuery,
                inlineChosenMapItem: $inlineChosenMapItem,
                showMapPickerSheet: $showMapPickerSheet,
                inlineFieldIsFocused: inlineFieldIsFocused,
                onInlineQueryChanged: onInlineQueryChanged,
                onClearInlineQuery: onClearInlineQuery,
                onMapPickerDismiss: onMapPickerDismiss,
                onMapItemPicked: onMapItemPicked,
                onCancelPassengerFlow: onCancelPassengerFlow,
                onCompletionSelected: onCompletionSelected
            )

            DashboardTopBarResultsDropdown(
                vm: vm,
                inlineCompleter: inlineCompleter,
                showingInlineSearch: showingInlineSearch,
                inlineQuery: inlineQuery,
                onCompletionSelected: onCompletionSelected
            )
        }
    }

    private var isPassenger: Bool {
        role.lowercased().contains("passenger")
    }
}
