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

    private let searchBarHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 8) {
            header
            searchRow
            resultsDropdown
        }
    }

    private var isPassenger: Bool {
        role.lowercased().contains("passenger")
    }

    private var header: some View {
        HStack {
            Text("Savari.")
                .font(.largeTitle.monospacedDigit())
                .foregroundColor(.primary)

            Spacer()

            Circle()
                .fill(vm.isRealtimeActive ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 12, height: 12)

            Menu {
                Button(role: .destructive, action: onSignOut) {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Material.ultraThin)
                    .clipShape(Circle())
            }
            .disabled(isSigningOut)
        }
    }

    private var searchRow: some View {
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
                if vm.passengerFlow == .searching && showingInlineSearch {
                    TextField("Where to?", text: $inlineQuery)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 10)
                        .padding(.trailing, 6)
                        .focused(inlineFieldIsFocused)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                inlineFieldIsFocused.wrappedValue = true
                            }
                        }
                        .onChange(of: inlineQuery) { _, new in
                            onInlineQueryChanged(new)
                        }
                        .onSubmit {
                            if let first = inlineCompleter.completions.first {
                                onCompletionSelected(first)
                            }
                        }
                } else {
                    Button {
                        vm.passengerFlow = .searching
                        showingInlineSearch = true
                    } label: {
                        HStack {
                            Text(destinationText.isEmpty ? "Where to?" : destinationText)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(destinationText.isEmpty ? .secondary : .primary)
                            Spacer()
                        }
                    }
                }
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

    private var mapPickerButton: some View {
        Button {
            if vm.passengerFlow == .idle {
                vm.passengerFlow = .searching
            }
            showingInlineSearch = false
            inlineQuery = ""
            inlineCompleter.update(query: "")
            showMapPickerSheet = true
        } label: {
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
        if isPassenger,
           vm.passengerFlow == .searching
            || vm.passengerFlow == .preview
            || vm.passengerFlow == .confirming {
            Button("Cancel", action: onCancelPassengerFlow)
                .foregroundColor(.primary)
                .padding(.leading, 6)
        }
    }

    @ViewBuilder
    private var resultsDropdown: some View {
        if vm.passengerFlow == .searching && showingInlineSearch {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if inlineCompleter.completions.isEmpty && inlineQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                            HStack {
                                Text("Type to search destinations or long-press on the map")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        } else {
                            ForEach(inlineCompleter.completions) { item in
                                Button {
                                    onCompletionSelected(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.body)
                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                }
                                Divider()
                                    .padding(.leading)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
                .background(Material.ultraThin)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06)))
                .padding(.horizontal, 4)
            }
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
