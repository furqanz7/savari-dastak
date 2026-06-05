import SwiftUI
@preconcurrency import Foundation
import MapKit
import Combine
import Supabase
import CoreLocation
import Realtime

enum PassengerFlowState {
    case idle
    case searching
    case preview
    case confirming
    case matching
    case accepted
    case enRoute
    case completed
}

func uuidStringsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs, let rhs else { return false }
    if let leftUUID = UUID(uuidString: lhs), let rightUUID = UUID(uuidString: rhs) {
        return leftUUID == rightUUID
    }
    return lhs.caseInsensitiveCompare(rhs) == .orderedSame
}

final class DashboardViewModelRealtime: ObservableObject {
    @Published var drivers: [Driver] = []
    @Published var route: Route
    @Published var isRealtimeActive: Bool = false
    @Published var rideRequested: Bool = false
    @Published var rideAccepted: Bool = false
    @Published var selectedRide: Ride = Ride()
    @Published var incomingRideRequests: [[String:Any]] = []
    @Published var activeRideRow: [String:Any]? = nil
    @Published var driverBoardingCodeEntry: String = ""
    @Published var isVerifyingBoardingCode: Bool = false
    @Published var boardingCodeVerified: Bool = false
    // Passenger-mode options
    @Published var fareAuto: Double? = nil
    @Published var fareBike: Double? = nil
    @Published var etaAutoSeconds: Int? = nil
    @Published var etaBikeSeconds: Int? = nil
    @Published var chosenTransportOption: String? = nil  // "Auto" or "Bike"
    @Published var assignedDriver: Driver? = nil
    @Published var assignedDriverETASeconds: Int? = nil
    @Published var waitSeconds: Int = 0
    @Published var waitChargeApplied: Bool = false
    @Published var isOnline: Bool = false
    @Published var passengerFlow: PassengerFlowState = .idle
    
    // Added driver flow state machine
    enum DriverFlow: String { case idle, awaitingOTP, verified, inProgress, completed }
    @Published var driverFlow: DriverFlow = .idle
    
    var waitTimer: Timer? = nil
    var assignedDriverUnsub: (() -> Void)? = nil
    private var rideRequestsCancel: (() -> Void)? = nil
    private var realtimeCancel: (() -> Void)? = nil
    private var tickTimer: AnyCancellable? = nil
    private var gpsCancellable: AnyCancellable?
    private var driverPublishTask: Task<Void, Never>? = nil
    
    private let role: String

    func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func jsonArray(from data: Data) -> [[String: Any]]? {
        try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    func jsonBool(from data: Data) -> Bool? {
        try? JSONDecoder().decode(Bool.self, from: data)
    }
    
    // IMPORTANT: initializer is synchronous (no async). avoid awaiting inside init.
    init(route: Route, role: String) {
        self.route = route
        self.role = role
        self.drivers = [] // start empty; fetchInitialDrivers() will populate
        
        startTickTimer()
        
        if role.lowercased().contains("driver") {
            GPSLocationPusher.shared.start()
            gpsCancellable = GPSLocationPusher.shared.$current
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] coord in
                    guard let self = self else { return }
                    if let auth = SavariSessionStore.authToken, let uuid = UUID(uuidString: auth) {
                        if let idx = self.drivers.firstIndex(where: { $0.id == uuid }) {
                            self.drivers[idx].coordinate = coord
                        } else {
                            let driver = Driver(id: uuid, coordinate: coord, name: "You", color: .mint)
                            self.drivers.insert(driver, at: 0)
                        }
                    } else {
                        if !self.drivers.isEmpty {
                            self.drivers[0].coordinate = coord
                        }
                    }
                }
        } else {
            GPSLocationPusher.shared.start()
        }
    }
    
    // New async starter
    // in DashboardViewModelRealtime.start()
    func start() async {
        await subscribeToDriverLocations()
        await fetchInitialDrivers()
    }
    
    func goOnline(driverId: String) {
        Task {
            // Idempotent guard: if already online, do nothing
            let alreadyOnline = await MainActor.run { () -> Bool in
                if self.isOnline { return true }
                self.isOnline = true
                return false
            }
            if alreadyOnline {
                SavariLog.debug("[VM] already online — ignoring goOnline")
                return
            }
            
            SavariLog.debug("[VM] goOnline called for driverId:", driverId)
            // mark role so GPSLocationPusher.publishCoordinateIfDriver will allow publishing
            SavariSessionStore.setLoggedIn(userId: driverId, role: "driver")
            
            // Cancel any existing publish task or subscription (safe cleanup)
            driverPublishTask?.cancel()
            driverPublishTask = nil
            rideRequestsCancel?()
            rideRequestsCancel = nil
            
            // Start Realtime subscription for incoming ride requests
            rideRequestsCancel = await RealtimeManager.shared.subscribeRideRequests { [weak self] payload in
                guard let self = self else { return }
                if let new = payload["new"] as? [String:Any] {
                    SavariLog.debug("[VM][DEBUG] ride payload new:", new)
                    let status = (new["status"] as? String) ?? ""
                    if status == "requested" {
                        if uuidStringsMatch(new["passenger_id"] as? String, driverId) { return }
                        // dedupe by id
                        let id = new["id"] as? String
                        if let id = id, self.incomingRideRequests.firstIndex(where: { ($0["id"] as? String) == id }) == nil {
                            Task { @MainActor in self.incomingRideRequests.append(new) }
                        }
                    } else {
                        // if it's assigned/whatever, remove from incoming list (update)
                        if let id = new["id"] as? String {
                            if let idx = self.incomingRideRequests.firstIndex(where: { ($0["id"] as? String) == id }) {
                                Task { @MainActor in self.incomingRideRequests.remove(at: idx) }
                            }
                            // if assigned to me, auto-load the active ride row
                            if status == "assigned", let assignedId = new["assigned_driver_id"] as? String,
                               uuidStringsMatch(assignedId, SavariSessionStore.authToken) {
                                Task { await self.loadActiveRideRowIfNeeded(rideId: id) }
                            }
                        }
                    }
                }
            }
            
            do {
                let resp = try await SupabaseManager.shared.client
                    .from("rides")
                    .select()
                    .eq("status", value: "requested")
                    .execute()
                
                if let rows = self.jsonArray(from: resp.data) {
                    await MainActor.run {
                        for row in rows {
                            // ignore rides created by same driver (defensive)
                            if uuidStringsMatch(row["passenger_id"] as? String, driverId) { continue }
                            // dedupe by id
                            if self.incomingRideRequests.firstIndex(where: { ($0["id"] as? String) == (row["id"] as? String) }) == nil {
                                self.incomingRideRequests.append(row)
                            }
                        }
                    }
                }
            } catch {
                SavariLog.debug("[VM] initial fetch requested rides failed:", error)
            }
            
            // Update UI state
            await MainActor.run {
                self.isRealtimeActive = true
            }
            
            // Immediately publish current location if available
            if let coord = GPSLocationPusher.shared.current {
                SavariLog.debug("[VM] immediate upsert coord:", coord)
                await RideService.shared.upsertDriverLocation(driverId: driverId, lat: coord.latitude, lon: coord.longitude)
            } else {
                SavariLog.debug("[VM] GPSLocationPusher.current is nil at goOnline")
            }
            
            // Start a periodic task that ensures we keep the driver row alive while online.
            driverPublishTask?.cancel()
        }
    }
    
    func stopOnline() {
        SavariLog.debug("[VM] stopOnline called")
        rideRequestsCancel?()
        rideRequestsCancel = nil
        incomingRideRequests.removeAll()
        isOnline = false
        
        driverPublishTask?.cancel()
        driverPublishTask = nil
        
        SavariSessionStore.setLastRole(nil)
        // Keep authToken for login persistence; full sign-out clears it from DashboardView.
        
        Task { @MainActor in
            self.isRealtimeActive = false
        }
    }
    
    var rideUpdateCancel: (() -> Void)? = nil
    
    func stopSubscribingMyRide() { rideUpdateCancel?(); rideUpdateCancel = nil }
    
    private func fetchInitialDrivers() async {
        do {
            let response = try await SupabaseManager.shared.client.from("driver_locations").select().execute()
            if let arr = jsonArray(from: response.data) {
                let rows = parseDriverRows(arr)
                await MainActor.run { self.drivers = rows }
            }
        } catch {
            SavariLog.debug("fetchInitialDrivers error:", error)
        }
    }
    
    private func parseDriverRows(_ rows: [[String: Any]]) -> [Driver] {
        var drivers: [Driver] = []
        for row in rows {
            if let idStr = row["driver_id"] as? String,
               let lat = row["latitude"] as? Double,
               let lon = row["longitude"] as? Double {
                let uuid = UUID(uuidString: idStr) ?? UUID()
                let name = driverMapLabel(for: uuid)
                drivers.append(Driver(id: uuid,
                                      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                      name: name,
                                      color: .blue))
            }
        }
        return drivers
    }

    private func driverMapLabel(for uuid: UUID) -> String {
        if uuidStringsMatch(uuid.uuidString, SavariSessionStore.authToken) {
            return "You"
        }
        return "Driver"
    }
    
    deinit { stopAll() }
    
    func startTickTimer() {
        tickTimer?.cancel()
        tickTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.selectedRide.tick() }
    }
    
    func stopAll() {
        tickTimer?.cancel()
        gpsCancellable?.cancel()
        realtimeCancel?()
        realtimeCancel = nil
        if role.lowercased().contains("driver") { GPSLocationPusher.shared.stop() }
    }
    
    func subscribeToDriverLocations() async {
        realtimeCancel?()
        isRealtimeActive = true
        realtimeCancel = await RealtimeManager.shared.subscribeDriverLocations { [weak self] incoming in
            guard let self = self else { return }
            Task { @MainActor in
                for d in incoming {
                    if let idx = self.drivers.firstIndex(where: { $0.id == d.id }) {
                        // treat (0,0) as delete
                        if d.coordinate.latitude == 0 && d.coordinate.longitude == 0 {
                            self.drivers.remove(at: idx)
                        } else {
                            let old = self.drivers[idx]
                            self.drivers[idx] = Driver(id: old.id, coordinate: d.coordinate, name: old.name, color: old.color)
                        }
                    } else {
                        // new driver
                        Task { @MainActor in
                            self.drivers.append(d)
                        }
                    }
                }
            }
        }
    }
    
    // Call this after a ride is accepted (or after subscribeToMyRide triggers assignment)
    func loadActiveRideRowIfNeeded(rideId: String) async {
        do {
            let resp = try await SupabaseManager.shared.client
                .from("rides")
                .select()
                .eq("id", value: rideId)
                .single()
                .execute()
            if let dict = jsonObject(from: resp.data) {
                await MainActor.run { self.activeRideRow = dict }
            }
        } catch {
            SavariLog.debug("loadActiveRideRowIfNeeded error:", error)
        }
    }
}
