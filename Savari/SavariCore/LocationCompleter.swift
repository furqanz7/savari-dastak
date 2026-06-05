import MapKit
@preconcurrency import Foundation
import Combine

final class LocationCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct CompletionItem: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let subtitle: String
        let mapItem: MKMapItem?
        let completion: MKLocalSearchCompletion?
    }

    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var completions: [CompletionItem] = []

    var region: MKCoordinateRegion? {
        didSet {
            if let region {
                completer.region = region
            }
        }
    }

    private let completer = MKLocalSearchCompleter()
    private let querySubject = PassthroughSubject<String, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var directSearchCancellable: AnyCancellable?

    override init() {
        super.init()

        completer.delegate = self
        completer.resultTypes = .address
        if #available(iOS 16.0, *) {
            completer.pointOfInterestFilter = .some(.includingAll)
        }

        querySubject
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(220), scheduler: RunLoop.main)
            .sink { [weak self] fragment in
                self?.setQueryFragment(fragment)
            }
            .store(in: &cancellables)
    }

    func update(query: String) {
        querySubject.send(query)

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        directSearchCancellable?.cancel()
        directSearchCancellable = Just(trimmedQuery)
            .delay(for: .milliseconds(160), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard !query.isEmpty else { return }
                self?.runDirectSearch(query: query, resultLimit: 12)
            }
    }

    func completer(_ completer: MKLocalSearchCompleter, didUpdateResults results: [MKLocalSearchCompletion]) {
        DispatchQueue.main.async {
            self.suggestions = results
            self.completions = results.map {
                CompletionItem(title: $0.title, subtitle: $0.subtitle, mapItem: nil, completion: $0)
            }
            SavariLog.debug("[LocationCompleter] got \(results.count) suggestions for '\(completer.queryFragment)'")
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let nsError = error as NSError
        SavariLog.debug("[LocationCompleter] didFailWithError domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")

        DispatchQueue.main.async {
            self.suggestions = []
            self.completions = []
        }

        let fallbackQuery = completer.queryFragment.isEmpty ? "Point of Interest" : completer.queryFragment
        runDirectSearch(query: fallbackQuery, resultLimit: 10)
    }

    private func setQueryFragment(_ fragment: String) {
        if fragment.isEmpty {
            suggestions = []
            completions = []
            completer.queryFragment = ""
            return
        }

        completer.queryFragment = fragment
    }

    private func runDirectSearch(query: String, resultLimit: Int) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = searchRegion

        MKLocalSearch(request: request).start { [weak self] response, error in
            guard let self else { return }

            if let error {
                SavariLog.debug("[LocationCompleter][DirectSearch] error:", error.localizedDescription)
                return
            }

            guard let mapItems = response?.mapItems, !mapItems.isEmpty else {
                return
            }

            DispatchQueue.main.async {
                self.completions = mapItems.prefix(resultLimit).map { Self.completionItem(from: $0) }
                SavariLog.debug("[LocationCompleter][DirectSearch] found \(mapItems.count) items for '\(query)'")
            }
        }
    }

    private var searchRegion: MKCoordinateRegion {
        if let region {
            return region
        }

        let candidate = completer.region
        if candidate.span.latitudeDelta != 0 && candidate.span.longitudeDelta != 0 {
            return candidate
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
    }

    private static func completionItem(from mapItem: MKMapItem) -> CompletionItem {
        CompletionItem(
            title: mapItem.name ?? (mapItem.placemark.title ?? "Unknown"),
            subtitle: mapItem.placemark.title ?? "",
            mapItem: mapItem,
            completion: nil
        )
    }
}
