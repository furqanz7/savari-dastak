import CoreLocation
import Foundation
import MarketplaceDesignSystem
import SwiftUI
import WeatherKit

enum DastakSceneWeatherChoice: String {
    case connected, notNow
    static let key = "dastak.scene-weather.choice.v1"
}

/// Separate from delivery addresses. Opt-in, coarse coordinates, no stored location.
@MainActor
final class DastakSceneWeather: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared: DastakSceneWeather = {
        #if DEBUG
        // Isolate first-install UI verification from the user's saved weather choice.
        if ProcessInfo.processInfo.arguments.contains("-DastakWeatherFirstLaunchPreview"),
           let defaults = UserDefaults(suiteName: "dastak.scene-weather.first-launch-preview") {
            return DastakSceneWeather(defaults: defaults)
        }
        #endif
        return DastakSceneWeather()
    }()
    @Published private(set) var status = "Time-only sky · live weather not connected"
    @Published private(set) var enabled = false
    @Published private(set) var attribution: WeatherAttribution?
    private let manager = CLLocationManager()
    private var snapshot: DastakEnvironmentWeather?
    private var observedAt: Date?
    private var lastAttempt: Date?
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var revision = UUID()
    private var sceneActive = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(); manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        enabled = defaults.string(forKey: DastakSceneWeatherChoice.key) == DastakSceneWeatherChoice.connected.rawValue
        if enabled { status = "Connecting nearby-area weather…" }
    }
    var needsFirstLaunchChoice: Bool { defaults.string(forKey: DastakSceneWeatherChoice.key) == nil }
    func skipFirstLaunchWeather() {
        defaults.set(DastakSceneWeatherChoice.notNow.rawValue, forKey: DastakSceneWeatherChoice.key)
    }
    func current(at date: Date) -> DastakEnvironmentWeather {
        if let snapshot, let observedAt, abs(date.timeIntervalSince(observedAt)) <= 3600 { return snapshot }
        return .localClock(date)
    }
    func enable() {
        defaults.set(DastakSceneWeatherChoice.connected.rawValue, forKey: DastakSceneWeatherChoice.key)
        enabled = true; status = "Waiting for location permission…"
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { resumeIfAllowed() }
    }
    func disable() {
        defaults.set(DastakSceneWeatherChoice.notNow.rawValue, forKey: DastakSceneWeatherChoice.key)
        revision = UUID()
        enabled = false; task?.cancel(); task = nil; deadline?.cancel(); deadline = nil; manager.stopUpdatingLocation()
        snapshot = nil; observedAt = nil; lastAttempt = nil; attribution = nil
        status = "Time-only sky · live weather not connected"
    }
    func pause() { revision = UUID(); task?.cancel(); task = nil; deadline?.cancel(); deadline = nil; manager.stopUpdatingLocation() }
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active { resumeIfAllowed() } else { pause() }
    }
    func resumeIfAllowed() {
        guard sceneActive, enabled, task == nil else { return }
        guard lastAttempt == nil || Date().timeIntervalSince(lastAttempt!) >= 900 else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: status = "Location unavailable · time-only sky"
        default: break
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            pause(); snapshot = nil; observedAt = nil; status = "Location unavailable · time-only sky"
        } else { resumeIfAllowed() }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        status = "Location unavailable · time-only sky"
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard sceneActive, enabled, task == nil, let fix = locations.last else { return }
        guard fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 120 else { return }
        // Only a rounded nearby-area coordinate reaches Apple Weather. Delivery
        // addresses, Dastak credentials and device-precision fixes stay out of it.
        let coarse = Self.weatherLocation(fix)
        lastAttempt = Date(); status = "Fetching nearby-area weather…"
        let generation = revision
        deadline = Task { [weak self] in
            do { try await Task.sleep(for:.seconds(12)) } catch { return }
            guard let self, self.revision == generation else { return }
            self.revision = UUID(); self.task?.cancel(); self.task = nil; self.deadline = nil
            self.snapshot = nil; self.observedAt = nil; self.attribution = nil
            self.status = "Weather unavailable · time-only sky"
        }
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.revision == generation {
                    self.task = nil; self.deadline?.cancel(); self.deadline = nil
                }
            }
            do {
                async let current = WeatherService.shared.weather(for:coarse,including:.current)
                async let credit = WeatherService.shared.attribution
                let (value,attribution) = try await (current,credit)
                guard !Task.isCancelled, self.sceneActive, self.enabled, self.revision == generation else { return }
                let wind=value.wind.speed.converted(to:.kilometersPerHour).value
                // Foundation has no millimetres/hour UnitSpeed on all supported OSes.
                let rain=value.precipitationIntensity.converted(to:.metersPerSecond).value * 3_600_000
                guard abs(value.date.timeIntervalSinceNow) < 3600,
                      [value.cloudCover,wind,rain].allSatisfy(\.isFinite),
                      (0...1).contains(value.cloudCover), wind >= 0, rain >= 0,
                      attribution.legalPageURL.scheme == "https" else { throw CocoaError(.coderReadCorrupt) }
                self.attribution = attribution
                self.snapshot = .init(daylight:value.isDaylight ? 1 : 0,cloud:value.cloudCover,
                    wind:min(150,wind),precipitation:min(20,rain),
                    snow:[.snow,.heavySnow,.blizzard,.blowingSnow,.flurries,.sunFlurries,.wintryMix].contains(value.condition))
                self.observedAt = value.date
                self.status = "Nearby-area weather · updated \(value.date.formatted(date:.omitted,time:.shortened)) · Apple Weather"
            } catch {
                guard !Task.isCancelled, self.revision == generation else { return }
                self.snapshot = nil; self.observedAt = nil; self.attribution = nil
                self.status = "Weather unavailable · time-only sky"
            }
        }
    }
    static func weatherLocation(_ fix: CLLocation) -> CLLocation {
        CLLocation(latitude:(fix.coordinate.latitude*100).rounded()/100,
                   longitude:(fix.coordinate.longitude*100).rounded()/100)
    }
}

public extension View {
    /// Mounted before authentication so the outside sign-in scenery can use weather.
    func dastakFirstLaunchWeather() -> some View { modifier(DastakFirstLaunchWeather()) }
}

private struct DastakFirstLaunchWeather: ViewModifier {
    @ObservedObject private var weather = DastakSceneWeather.shared
    @Environment(\.scenePhase) private var phase
    @State private var showingChoice = false

    func body(content: Content) -> some View {
        content
            .task(id: phase) {
                if phase == .active, weather.needsFirstLaunchChoice {
                    showingChoice = true
                }
            }
            .alert("Connect local weather?", isPresented: $showingChoice) {
                Button("Not now", role: .cancel) { weather.skipFirstLaunchWeather() }
                Button("Connect") { weather.enable() }
            } message: {
                Text("Bring the sign-in scenery to life with weather near you. Connect sends rounded nearby-area coordinates to Apple Weather. You can change this in Settings.")
            }
    }
}

/// Mounted in the authentication footer, not on the full-screen scenery behind it.
public struct DastakSceneWeatherCredit: View {
    @ObservedObject private var weather = DastakSceneWeather.shared
    public init() {}
    public var body: some View {
        if let attribution = weather.attribution {
            DastakWeatherAttribution(attribution: attribution, overScenery: true)
        }
    }
    #if DEBUG
    /// Layout-only credit using the same fallback mark, without location or network access.
    public static var layoutPreview: some View {
        DastakWeatherAttribution(layoutPreview: true)
    }
    #endif
}

struct DastakSceneWeatherControls: View {
    @ObservedObject private var weather = DastakSceneWeather.shared
    @State private var consent = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Scene weather").font(.headline)
            Text(weather.status).font(.footnote).foregroundStyle(.secondary)
            MarketplaceFeedbackButton(weather.enabled ? "Disconnect live weather" : "Connect local weather") {
                if weather.enabled { weather.disable() } else { consent = true }
            }
            .frame(minHeight:44)
            if let attribution = weather.attribution { DastakWeatherAttribution(attribution:attribution) }
        }
        .padding(12)
        .marketplaceFlatSurface()
        .alert("Connect local weather?",isPresented:$consent) {
            Button("Cancel",role:.cancel) {}
            Button("Connect") { weather.enable() }
        } message: {
            Text("Your location is requested only for scenery. Rounded nearby-area coordinates are sent to Apple Weather. Your delivery address and Dastak account details are not sent. You can disconnect here.")
        }
    }
}

private struct DastakWeatherAttribution: View {
    let legalPageURL: URL
    let combinedMarkLightURL: URL?
    let combinedMarkDarkURL: URL?
    let overScenery: Bool
    @Environment(\.colorScheme) private var scheme
    init(attribution: WeatherAttribution, overScenery: Bool = false) {
        legalPageURL = attribution.legalPageURL
        combinedMarkLightURL = attribution.combinedMarkLightURL
        combinedMarkDarkURL = attribution.combinedMarkDarkURL
        self.overScenery = overScenery
    }
    #if DEBUG
    init(layoutPreview: Bool) {
        legalPageURL = URL(string:"https://weatherkit.apple.com/legal-attribution.html")!
        combinedMarkLightURL = nil; combinedMarkDarkURL = nil; overScenery = true
    }
    #endif
    private var usesLightMark: Bool { overScenery || scheme == .dark }
    var body: some View {
        Link(destination:legalPageURL) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing:9) {
                    weatherMark
                    Rectangle()
                        .fill(.primary.opacity(0.22))
                        .frame(width:1,height:12)
                        .accessibilityHidden(true)
                    dataSources
                }
                .fixedSize(horizontal:true,vertical:false)
                VStack(spacing:6) {
                    weatherMark
                    dataSources
                }
            }
            .foregroundStyle(overScenery ? Color.white : Color.primary)
            .padding(.horizontal,10).padding(.vertical,7)
            .background {
                if overScenery {
                    RoundedRectangle(cornerRadius:10,style:.continuous)
                        .fill(Color.black.opacity(0.60))
                        .overlay {
                            RoundedRectangle(cornerRadius:10,style:.continuous)
                                .strokeBorder(Color.white.opacity(0.12),lineWidth:0.5)
                        }
                } else {
                    RoundedRectangle(cornerRadius:10,style:.continuous).fill(.regularMaterial)
                }
            }
            .frame(minHeight:44,alignment:.topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apple Weather. View weather data sources.")
    }

    private var weatherMark: some View {
        AsyncImage(url:usesLightMark ? combinedMarkLightURL : combinedMarkDarkURL) { image in
            image.resizable().scaledToFit().frame(width:84,height:14)
        } placeholder: {
            Label("Weather",systemImage:"apple.logo")
                .font(.system(size:12,weight:.medium)).frame(width:84,height:14)
        }
        .accessibilityHidden(true)
    }

    private var dataSources: some View {
        HStack(spacing:4) {
            Text("Data sources")
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal:false,vertical:true)
            Image(systemName:"arrow.up.right")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
    }
}
