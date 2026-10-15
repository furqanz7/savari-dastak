import CoreLocation
import Foundation
import MarketplaceDesignSystem
import SwiftUI

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
    private let manager = CLLocationManager()
    private var snapshot: DastakEnvironmentWeather?
    private var observedAt: Date?
    private var lastAttempt: Date?
    private var task: Task<Void, Never>?
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
    var provider: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey:"DASTAK_SCENE_WEATHER_URL") as? String,
           let url = URL(string:value), url.scheme == "https", url.user == nil, url.password == nil { return url }
        #if DEBUG
        return URL(string:"https://api.open-meteo.com/v1/forecast")
        #else
        // Do not silently use a noncommercial public weather endpoint in a commercial release.
        return nil
        #endif
    }
    func current(at date: Date) -> DastakEnvironmentWeather {
        if let snapshot, let observedAt, abs(date.timeIntervalSince(observedAt)) <= 3600 { return snapshot }
        return .localClock(date)
    }
    func enable() {
        defaults.set(DastakSceneWeatherChoice.connected.rawValue, forKey: DastakSceneWeatherChoice.key)
        guard provider != nil else { status = "Time-only sky · live weather service is not configured"; return }
        enabled = true; status = "Waiting for location permission…"
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { resumeIfAllowed() }
    }
    func disable() {
        defaults.set(DastakSceneWeatherChoice.notNow.rawValue, forKey: DastakSceneWeatherChoice.key)
        revision = UUID()
        enabled = false; task?.cancel(); task = nil; manager.stopUpdatingLocation()
        snapshot = nil; observedAt = nil; lastAttempt = nil
        status = "Time-only sky · live weather not connected"
    }
    func pause() { revision = UUID(); task?.cancel(); task = nil; manager.stopUpdatingLocation() }
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active { resumeIfAllowed() } else { pause() }
    }
    func resumeIfAllowed() {
        guard sceneActive, enabled, provider != nil, task == nil else { return }
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
        guard sceneActive, enabled, task == nil, let fix = locations.last, let provider else { return }
        guard fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 120 else { return }
        var url = URLComponents(url:provider,resolvingAgainstBaseURL:false)!
        // No device-precision coordinates, saved address, account token or user identifier.
        url.queryItems = [
            .init(name:"latitude",value:String(format:"%.2f",fix.coordinate.latitude)),
            .init(name:"longitude",value:String(format:"%.2f",fix.coordinate.longitude)),
            .init(name:"current",value:"cloud_cover,precipitation,weather_code,wind_speed_10m,is_day"),
            .init(name:"timezone",value:"auto"),.init(name:"timeformat",value:"unixtime")
        ]
        guard let endpoint = url.url else { return }
        lastAttempt = Date(); status = "Fetching nearby-area weather…"
        let generation = revision
        task = Task { [weak self] in
            guard let self else { return }; defer { if self.revision == generation { self.task = nil } }
            do {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 12; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
                let session = URLSession(configuration:config); defer { session.invalidateAndCancel() }
                let (data,response) = try await session.data(from:endpoint)
                guard !Task.isCancelled, self.sceneActive, self.enabled, self.revision == generation else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let value = try JSONDecoder().decode(WeatherResponse.self,from:data).current
                guard abs(Date().timeIntervalSince1970-value.time) < 3600,
                      [value.cloud_cover,value.precipitation,value.wind_speed_10m].allSatisfy(\.isFinite),
                      value.cloud_cover >= 0, value.cloud_cover <= 100, value.precipitation >= 0,
                      value.wind_speed_10m >= 0, [0,1].contains(value.is_day) else { throw CocoaError(.coderReadCorrupt) }
                self.snapshot = .init(daylight:value.is_day == 1 ? 1 : 0,cloud:value.cloud_cover/100,
                    wind:min(150,value.wind_speed_10m),precipitation:min(20,value.precipitation),
                    snow:[71,73,75,77,85,86].contains(value.weather_code))
                self.observedAt = Date(timeIntervalSince1970:value.time)
                self.status = "Nearby-area weather · updated \(self.observedAt!.formatted(date:.omitted,time:.shortened)) · Open-Meteo"
            } catch {
                guard !Task.isCancelled, self.revision == generation else { return }
                self.snapshot = nil; self.observedAt = nil; self.status = "Weather unavailable · time-only sky"
            }
        }
    }
    private struct WeatherResponse: Decodable {
        let current: Reading
        struct Reading: Decodable {
            let time,cloud_cover,precipitation,wind_speed_10m: Double
            let weather_code,is_day: Int
        }
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
                if phase == .active, weather.needsFirstLaunchChoice, weather.provider != nil {
                    showingChoice = true
                }
            }
            .alert("Connect local weather?", isPresented: $showingChoice) {
                Button("Not now", role: .cancel) { weather.skipFirstLaunchWeather() }
                Button("Connect") { weather.enable() }
            } message: {
                Text("Bring the sign-in scenery to life with weather near you. Connect uses your approximate location and sends rounded nearby-area coordinates to \(weather.provider?.host ?? "the weather service"). You can change this in Settings.")
            }
    }
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
            .disabled(weather.provider == nil)
            if weather.provider == nil { Text("Live weather service is not configured. Day/night still follows the device clock.").font(.footnote) }
        }
        .padding(12)
        .marketplaceFlatSurface()
        .alert("Connect local weather?",isPresented:$consent) {
            Button("Cancel",role:.cancel) {}
            Button("Connect") { weather.enable() }
        } message: {
            Text("Your location is requested only for scenery. Rounded nearby-area coordinates are sent to the configured weather service (Open-Meteo in this development build). Your delivery address and account details are not sent. You can disconnect here.")
        }
    }
}
