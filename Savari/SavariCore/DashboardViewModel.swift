import SwiftUI
@preconcurrency import Foundation
import Combine
import Supabase
import PostgREST
import CoreLocation

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

nonisolated func uuidStringsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
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
    @Published var driverBoardingCodeError: String? = nil
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
    enum DriverFlow: String { case idle, awaitingOTP, verified, inProgress, passengerCancelled, collectPayment }
    @Published var driverFlow: DriverFlow = .idle
    
    var waitTimer: Timer? = nil
    var assignedDriverUnsub: (() -> Void)? = nil
    var rideRequestsCancel: (() -> Void)? = nil
    var realtimeCancel: (() -> Void)? = nil
    var passengerRidePollingTask: Task<Void, Never>? = nil
    var driverIdleOfflineTask: Task<Void, Never>? = nil
    var driverRequestBacklogPollingTask: Task<Void, Never>? = nil
    var driverActiveRidePollingTask: Task<Void, Never>? = nil
    var assignedDriverId: String? = nil
    var tickTimer: AnyCancellable? = nil
    var gpsCancellable: AnyCancellable?
    var driverPublishTask: Task<Void, Never>? = nil
    
    private let role: String

    func jsonObject(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func jsonArray(from data: Data) -> [[String: Any]]? {
        try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    func jsonBool(from data: Data) -> Bool? {
        try? JSONDecoder().decode(Bool.self, from: data)
    }
    
    init(route: Route, role: String) {
        self.route = route
        self.role = role
        self.drivers = []
        
        startTickTimer()
        startGPSUpdates(for: role)
    }
    
    func start() async {
        await subscribeToDriverLocations()
        await fetchInitialDrivers()
    }
    
    var rideUpdateCancel: (() -> Void)? = nil
    
    func stopSubscribingMyRide() {
        rideUpdateCancel?()
        rideUpdateCancel = nil
        passengerRidePollingTask?.cancel()
        passengerRidePollingTask = nil
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
        rideUpdateCancel?()
        rideUpdateCancel = nil
        passengerRidePollingTask?.cancel()
        passengerRidePollingTask = nil
        driverIdleOfflineTask?.cancel()
        driverIdleOfflineTask = nil
        driverRequestBacklogPollingTask?.cancel()
        driverRequestBacklogPollingTask = nil
        driverActiveRidePollingTask?.cancel()
        driverActiveRidePollingTask = nil
        assignedDriverUnsub?()
        assignedDriverUnsub = nil
        realtimeCancel?()
        realtimeCancel = nil
        if role.lowercased().contains("driver") { GPSLocationPusher.shared.stop() }
    }
    
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
