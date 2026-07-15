import SwiftUI
import MapKit

struct DashboardTopBarSearchRow: View {
    let isPassenger: Bool
    @ObservedObject var vm: DashboardViewModelRealtime
    @ObservedObject var inlineCompleter: LocationCompleter
    @Binding var destinationText: String
    @Binding var showingInlineSearch: Bool
    @Binding var inlineQuery: String
    @Binding var inlineChosenMapItem: MKMapItem?
    @Binding var showMapPickerSheet: Bool
    var inlineFieldIsFocused: FocusState<Bool>.Binding
    let onInlineQueryChanged: (String) -> Void
    let onClearInlineQuery: () -> Void
    let onMapPickerDismiss: () -> Void
    let onMapItemPicked: (MKMapItem) -> Void
    let onCancelPassengerFlow: () -> Void
    let onCompletionSelected: (LocationCompleter.CompletionItem) -> Void

    private let searchBarHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 6) {
            searchPill
            mapPickerButton
            cancelButton
        }
    }

    private var searchPill: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")

            if isPassenger {
                passengerSearchContent
            }

            if vm.passengerFlow == .searching && showingInlineSearch && !inlineQuery.isEmpty {
                Button(action: onClearInlineQuery) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(height: searchBarHeight)
        .frame(maxWidth: .infinity)
        .background(Material.ultraThin)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
        .frame(maxWidth: 520)
    }

    @ViewBuilder
    private var passengerSearchContent: some View {
        if vm.passengerFlow == .searching && showingInlineSearch {
            TextField("Where to?", text: $inlineQuery)
                .textFieldStyle(.plain)
                .padding(.vertical, 10)
                .padding(.trailing, 6)
                .focused(inlineFieldIsFocused)
                .onAppear(perform: focusInlineField)
                .onChange(of: inlineQuery) { _, new in
                    onInlineQueryChanged(new)
                }
                .onSubmit(selectFirstCompletion)
        } else {
            Button(action: beginInlineSearch) {
                HStack {
                    Text(destinationText.isEmpty ? "Where to?" : destinationText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(destinationText.isEmpty ? .secondary : .primary)
                    Spacer()
                }
            }
        }
    }

    private var mapPickerButton: some View {
        Button(action: showMapPicker) {
            Image(systemName: "map")
                .font(.system(size: 16, weight: .semibold))
                .padding(10)
                .background(Material.ultraThin)
                .cornerRadius(10)
        }
        .sheet(isPresented: $showMapPickerSheet, onDismiss: onMapPickerDismiss) {
            MapPickerView(selectedItem: $inlineChosenMapItem) { item in
                onMapItemPicked(item)
            }
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        if isPassenger && (
            vm.passengerFlow == .searching ||
            vm.passengerFlow == .preview ||
            vm.passengerFlow == .confirming
        ) {
            Button("Cancel", action: onCancelPassengerFlow)
                .foregroundColor(.primary)
                .padding(.leading, 6)
        }
    }

    private func focusInlineField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            inlineFieldIsFocused.wrappedValue = true
        }
    }

    private func beginInlineSearch() {
        vm.passengerFlow = .searching
        showingInlineSearch = true
    }

    private func selectFirstCompletion() {
        if let first = inlineCompleter.completions.first {
            onCompletionSelected(first)
        }
    }

    private func showMapPicker() {
        if vm.passengerFlow == .idle {
            vm.passengerFlow = .searching
        }
        showingInlineSearch = false
        inlineQuery = ""
        inlineCompleter.update(query: "")
        showMapPickerSheet = true
    }
}
