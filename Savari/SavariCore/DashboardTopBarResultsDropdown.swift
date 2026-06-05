import SwiftUI

struct DashboardTopBarResultsDropdown: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    @ObservedObject var inlineCompleter: LocationCompleter
    let showingInlineSearch: Bool
    let inlineQuery: String
    let onCompletionSelected: (LocationCompleter.CompletionItem) -> Void

    var body: some View {
        if vm.passengerFlow == .searching && showingInlineSearch {
            VStack(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if shouldShowEmptyPrompt {
                            emptyPrompt
                        } else {
                            completionRows
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

    private var shouldShowEmptyPrompt: Bool {
        inlineCompleter.completions.isEmpty &&
        inlineQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var emptyPrompt: some View {
        HStack {
            Text("Type to search destinations or long-press on the map")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var completionRows: some View {
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
