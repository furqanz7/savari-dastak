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

private func uuidStringsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
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
    
    private var waitTimer: Timer? = nil
    private var assignedDriverUnsub: (() -> Void)? = nil
    private var rideRequestsCancel: (() -> Void)? = nil
    private var realtimeCancel: (() -> Void)? = nil
    private var tickTimer: AnyCancellable? = nil
    private var gpsCancellable: AnyCancellable?
    private var driverPublishTask: Task<Void, Never>? = nil
    
    private let role: String

    private func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func jsonArray(from data: Data) -> [[String: Any]]? {
        try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    private func jsonBool(from data: Data) -> Bool? {
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
                    if let auth = UserDefaults.standard.string(forKey: "authToken"), let uuid = UUID(uuidString: auth) {
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
                print("[VM] already online — ignoring goOnline")
                return
            }
            
            print("[VM] goOnline called for driverId:", driverId)
            // mark role so GPSLocationPusher.publishCoordinateIfDriver will allow publishing
            UserDefaults.standard.set("driver", forKey: "lastRole")
            // ensure authToken present for GPS pusher
            UserDefaults.standard.set(driverId, forKey: "authToken")
            
            // Cancel any existing publish task or subscription (safe cleanup)
            driverPublishTask?.cancel()
            driverPublishTask = nil
            rideRequestsCancel?()
            rideRequestsCancel = nil
            
            // Start Realtime subscription for incoming ride requests
            rideRequestsCancel = await RealtimeManager.shared.subscribeRideRequests { [weak self] payload in
                guard let self = self else { return }
                if let new = payload["new"] as? [String:Any] {
                    print("[VM][DEBUG] ride payload new:", new)
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
                               uuidStringsMatch(assignedId, UserDefaults.standard.string(forKey: "authToken")) {
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
                print("[VM] initial fetch requested rides failed:", error)
            }
            
            // Update UI state
            await MainActor.run {
                self.isRealtimeActive = true
            }
            
            // Immediately publish current location if available
            if let coord = GPSLocationPusher.shared.current {
                print("[VM] immediate upsert coord:", coord)
                await RideService.shared.upsertDriverLocation(driverId: driverId, lat: coord.latitude, lon: coord.longitude)
            } else {
                print("[VM] GPSLocationPusher.current is nil at goOnline")
            }
            
            // Start a periodic task that ensures we keep the driver row alive while online.
            driverPublishTask?.cancel()
        }
    }
    
    func stopOnline() {
        print("[VM] stopOnline called")
        rideRequestsCancel?()
        rideRequestsCancel = nil
        incomingRideRequests.removeAll()
        isOnline = false
        
        driverPublishTask?.cancel()
        driverPublishTask = nil
        
        UserDefaults.standard.removeObject(forKey: "lastRole")
        // Optionally keep authToken for login persistence, or remove if you want sign-out:
        // UserDefaults.standard.removeObject(forKey: "authToken")
        
        Task { @MainActor in
            self.isRealtimeActive = false
        }
    }
    
    private var rideUpdateCancel: (() -> Void)? = nil
    
    func stopSubscribingMyRide() { rideUpdateCancel?(); rideUpdateCancel = nil }
    
    private func fetchInitialDrivers() async {
        do {
            let response = try await SupabaseManager.shared.client.from("driver_locations").select().execute()
            if let arr = jsonArray(from: response.data) {
                let rows = parseDriverRows(arr)
                await MainActor.run { self.drivers = rows }
            }
        } catch {
            print("fetchInitialDrivers error:", error)
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
        if uuidStringsMatch(uuid.uuidString, UserDefaults.standard.string(forKey: "authToken")) {
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
            print("loadActiveRideRowIfNeeded error:", error)
        }
    }
    
    func driverArrived(rideId: String, driverId: String) async -> Bool {
        let ok = await RideService.shared.markArrived(rideId: rideId, driverId: driverId)
        if ok {
            await MainActor.run {
                var row = self.activeRideRow ?? [:]
                row["status"] = "arrived"
                self.activeRideRow = row
                self.waitSeconds = 0
                self.waitChargeApplied = false
            }
            // start local timer
            await MainActor.run {
                self.waitTimer?.invalidate()
                self.waitTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
                    guard let self = self else { return }
                    self.waitSeconds += 1
                    // if wait passes 120s and not applied -> call RPC once
                    if self.waitSeconds > 120 && !self.waitChargeApplied {
                        self.waitChargeApplied = true
                        Task {
                            _ = await RideService.shared.applyWaitingChargeNow(rideId: rideId)
                            // update activeRideRow to fetch latest waiting_charge
                            await self.loadActiveRideRowIfNeeded(rideId: rideId)
                        }
                    }
                }
            }
        }
        return ok
    }
    
    func verifyBoardingCodeAndBoard(rideId: String, code: String) async -> Bool {
        do {
            // fetch the ride row (we expect boarding_code stored)
            let fetch = try await SupabaseManager.shared.client
                .from("rides")
                .select("id,boarding_code")
                .eq("id", value: rideId)
                .single()
                .execute()
            
            if let dict = jsonObject(from: fetch.data), let expected = dict["boarding_code"] as? String {
                if expected == code {
                    let payload: [String: AnyEncodable] = [
                        "status": AnyEncodable("boarded")
                    ]
                    _ = try await SupabaseManager.shared.client
                        .from("rides")
                        .update(payload)
                        .eq("id", value: rideId)
                        .execute()
                    return true
                } else {
                    return false
                }
            }
        } catch {
            print("verifyBoardingCodeAndBoard error:", error)
        }
        return false
    }
    
    func startRideNow(rideId: String) async -> Bool {
        let ok = await RideService.shared.startRide(rideId: rideId)
        if ok { await MainActor.run { var copy = activeRideRow ?? [:]; copy["status"] = "in_progress"; self.activeRideRow = copy
        }
            do { self.waitTimer?.invalidate()
                self.waitTimer = nil
                self.waitSeconds = 0
            }
            do {
                self.assignedDriverUnsub?()
                self.assignedDriverUnsub = nil
                self.assignedDriver = nil
            }
        }
        return ok
    }
    
    func endRideNow(rideId: String) async -> Bool {
        let ok = await RideService.shared.endRideAndUnlockFare(rideId: rideId)
        if ok {
            await MainActor.run {
                var copy = self.activeRideRow ?? [:]
                copy["status"] = "completed"
                self.activeRideRow = copy
            }
            do {
                self.assignedDriverUnsub?()
                self.assignedDriverUnsub = nil
                self.assignedDriver = nil
            }
        }
        return ok
    }
    
    // driver accepts a ride using atomic RPC
    func acceptRide(rideId: String, driverId: String) async -> Bool {
        let ok = await RideService.shared.acceptRide(rideId: rideId, driverId: driverId)
        if ok {
            await loadActiveRideRowIfNeeded(rideId: rideId)
            await MainActor.run { self.rideAccepted = true }
        }
        return ok
    }
    
    // Convenience: accept using an incoming ride dictionary (from realtime/polling)
    func acceptIncomingRide(_ incomingRide: [String: Any]) {
        guard let rideId = incomingRide["id"] as? String,
              let driverId = UserDefaults.standard.string(forKey: "authToken") else { return }
        if uuidStringsMatch(incomingRide["passenger_id"] as? String, driverId) {
            print("accept blocked: driver cannot accept their own passenger ride")
            return
        }
        Task {
            // Optimistically remove from list
            await MainActor.run {
                if let idx = self.incomingRideRequests.firstIndex(where: { ($0["id"] as? String) == rideId }) {
                    self.incomingRideRequests.remove(at: idx)
                }
            }
            
            let ok = await RideService.shared.acceptRide(rideId: rideId, driverId: driverId)
            if ok {
                await self.loadActiveRideRowIfNeeded(rideId: rideId)
                await MainActor.run { self.rideAccepted = true }
            } else {
                // race: another driver accepted first; show toast and refresh list
                print("accept failed (likely accepted by someone else)")
                // optional: re-fetch requested rides or signal UI
                Task {
                    // re-fetch a few requested rides to update local state
                    // ... same fetch as in goOnline ...
                }
            }
            let currentLocation = GPSLocationPusher.shared.current
            await MainActor.run {
                self.incomingRideRequests.sort { lhs, rhs in
                    func distanceToPickup(_ row: [String:Any]) -> Double {
                        guard let plat = row["pickup_lat"] as? Double, let plon = row["pickup_lon"] as? Double,
                              let my = currentLocation else { return Double.greatestFiniteMagnitude }
                        return distanceMetersBetween(my, CLLocationCoordinate2D(latitude: plat, longitude: plon))
                    }
                    return distanceToPickup(lhs) < distanceToPickup(rhs)
                }
            }
        }
    }
    
    func driverCancelAssignedRide(rideId: String, driverId: String, reason: String = "") async -> Bool {
        do {
            let params: [String: AnyEncodable] = [
                "p_ride_id": AnyEncodable(rideId),
                "p_driver_id": AnyEncodable(driverId),
                "p_reason": AnyEncodable(reason)
            ]
            let resp = try await SupabaseManager.shared.client.rpc("driver_cancel_ride", params: params).execute()
            if let b = jsonBool(from: resp.data) { return b }
        } catch {
            print("driverCancelAssignedRide error:", error)
        }
        return false
    }
    @MainActor
    func cancelRideRequest() async {
        let rideId = selectedRide.orderID
        if rideId.isEmpty {
            print("[CancelRide] No rideId found")
            return
        }

        do {
            let payload: [String: AnyEncodable] = [
                "status": AnyEncodable("cancelled"),
                "cancelled_at": AnyEncodable(Date().iso8601String)
            ]
            _ = try await SupabaseManager.shared.client
                .from("rides")
                .update(payload)
                .eq("id", value: rideId)
                .execute()
            print("[CancelRide] Ride cancelled:", rideId)
        } catch {
            print("[CancelRide] Error:", error.localizedDescription)
        }
    }
    
    func updateFareEstimates(distanceMeters: CLLocationDistance) {
        let km = distanceMeters / 1000

        fareAuto = max(50, 20 + km * 12)
        fareBike = max(30, 10 + km * 8)

        // Default selection (Apple-style)
        if chosenTransportOption == nil {
            chosenTransportOption = "Auto"
            selectedRide.amount = fareAuto ?? 0
        }
    }
}
    
    // --- Wiring changes for DashboardViewModelRealtime.subscribeToMyRide ---
    extension DashboardViewModelRealtime {
        func subscribeToMyRide(rideId: String) async {
            // unsubscribe any existing ride subscription
            rideUpdateCancel?(); rideUpdateCancel = nil
            
            // Subscribe to the rides table for updates (existing helper)
            rideUpdateCancel = await RealtimeManager.shared.subscribeRideRequests { [weak self] payload in
                guard let self = self else { return }
                if let new = payload["new"] as? [String:Any], let id = new["id"] as? String, id == rideId {
                    Task { @MainActor in
                        // store latest row
                        self.activeRideRow = new
                        
                        // If an assigned driver has been set, subscribe to that driver's location
                        if let assigned = (new["assigned_driver_id"] as? String) ?? (new["driver_id"] as? String) {
                            // mark ride accepted (passenger sees driver on the way)
                            self.passengerFlow = .accepted
                            
                            // cancel any previous assigned-driver subscription
                            self.assignedDriverUnsub?()
                            self.assignedDriverUnsub = nil
                            
                            // subscribe to the assigned driver's location and keep the unsubscribe handle
                            Task {
                                self.assignedDriverUnsub = await RealtimeManager.shared.subscribeDriverLocation(driverId: assigned) { driver in
                                    Task { @MainActor in
                                        // update assignedDriver model used by the UI
                                        self.assignedDriver = driver
                                        
                                        // compute ETA driver -> pickup if pickup coords present on the active ride row
                                        if let plat = self.activeRideRow?["pickup_lat"] as? Double,
                                           let plon = self.activeRideRow?["pickup_lon"] as? Double {
                                            let pickupCoord = CLLocationCoordinate2D(latitude: plat, longitude: plon)
                                            let meters = distanceMetersBetween(driver.coordinate, pickupCoord)
                                            self.assignedDriverETASeconds = secondsFromMeters(meters, avgSpeedMetersPerSec: 8.0)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // react to status transitions (arrived, boarded, in_progress, completed, cancelled)
                        if let status = new["status"] as? String {
                            switch status {
                            case "arrived":
                                // driver has arrived — UI will show arrival state
                                self.passengerFlow = .enRoute
                            case "boarded":
                                self.boardingCodeVerified = true
                            case "in_progress":
                                self.passengerFlow = .enRoute
                            case "completed", "cancelled":
                                // cleanup assigned driver subscription
                                self.assignedDriverUnsub?()
                                self.assignedDriverUnsub = nil
                                self.assignedDriver = nil
                                self.rideAccepted = false
                                // optionally clear activeRideRow if you want
                            default:
                                break
                            }
                        }
                    }
                }
            }
        }
    }
