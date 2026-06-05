import SwiftUI
import Foundation
import MapKit
import CoreLocation
import UIKit
import Combine

// MARK: - DashboardView (realtime + GPS)
struct DashboardView: View {
    let role: String
    @StateObject private var vm: DashboardViewModelRealtime
    @AppStorage(SavariDefaultsKey.authToken) private var authToken: String?
    @AppStorage(SavariDefaultsKey.lastRole) private var lastRole: String?
    @AppStorage(SavariDefaultsKey.isOnboardingComplete) private var isOnboardingComplete: Bool = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var didCenterToUser: Bool = false
    @State private var isSigningOut: Bool = false
    
    // passenger UI state
    @State private var destinationText: String = ""
    // Removed @State private var chosenTransport
    
    // Inline search state
    @State private var showingInlineSearch: Bool = false
    @StateObject private var inlineCompleter = LocationCompleter()
    @State private var inlineQuery: String = ""
    @State private var inlineChosenMapItem: MKMapItem? = nil
    
    // flags to show markers on main map
    @State private var pickupCoordinate: CLLocationCoordinate2D? = nil
    @State private var destCoordinate: CLLocationCoordinate2D? = nil
    
    // Tracking & UI controls
    @State private var isTrackingUser: Bool = false
    
    // sheet-based MapPicker from top overlay
    @State private var showMapPickerSheet: Bool = false
    
    // cancelable task for async searches (so we can cancel in-flight work)
    @State private var inlineSearchTask: Task<Void, Never>? = nil
    
    @FocusState private var inlineFieldIsFocused: Bool
    init(role: String) {
        self.role = role
        let route = Route(start: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
                          end: CLLocationCoordinate2D(latitude: 28.62, longitude: 77.225))
        _vm = StateObject(wrappedValue: DashboardViewModelRealtime(route: route, role: role))
    }
    
    var body: some View {
        ZStack {
            Map(position: $mapPosition) {
                DashboardMapContent(
                    role: role,
                    drivers: vm.drivers,
                    selectedRide: vm.selectedRide,
                    assignedDriver: vm.assignedDriver,
                    activeRideRow: vm.activeRideRow,
                    pickupCoordinate: pickupCoordinate,
                    destCoordinate: destCoordinate,
                    showRouteOverlay: true,
                    onDriverTap: { coordinate in
                        withAnimation {
                            mapPosition = .region(
                                MKCoordinateRegion(
                                    center: coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                                )
                            )
                        }
                    }
                )
            }
            .ignoresSafeArea()
            .onReceive(GPSLocationPusher.shared.$current.compactMap { $0 }) { coord in
                if isTrackingUser || !didCenterToUser {
                    withAnimation(.easeInOut) {
                        mapPosition = .region(
                            MKCoordinateRegion(center: coord,
                                               span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
                        )
                    }
                    didCenterToUser = true
                }
            }
            .onChange(of: vm.passengerFlow) { flow in
                guard
                    flow == .accepted,
                    let driver = vm.assignedDriver
                else { return }

                withAnimation(.easeInOut(duration: 0.6)) {
                    mapPosition = .region(
                        MKCoordinateRegion(
                            center: driver.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                }
            }
            // PREVIEW: floating distance + continue pill ONLY
            if vm.passengerFlow == .preview {
                VStack {
                    Spacer()
                    DistanceETABox(
                        distanceMeters: vm.selectedRide.distanceMeters,
                        etaSeconds: TimeInterval(vm.selectedRide.etaSeconds)
                    ) {
                        withAnimation(.spring()) {
                            vm.passengerFlow = .confirming
                        }
                    }
                    .padding(.bottom, 28)
                }
                .zIndex(7)
            }

            // CONFIRM / MATCHING / ACCEPTED: real card
            if vm.passengerFlow == .confirming
                || vm.passengerFlow == .matching
                || vm.passengerFlow == .accepted {

                VStack {
                    Spacer()
                    RideFlowCard(
                        flow: vm.passengerFlow,
                        vm: vm,
                        onConfirm: {
                            Task { await performPassengerRequestFlow() }
                            vm.passengerFlow = .matching
                        },
                        onCancel: {
                            Task {
                                await vm.cancelRideRequest()
                                await MainActor.run {
                                    vm.passengerFlow = .idle
                                }
                            }
                        }
                    )
                    .frame(maxHeight: vm.passengerFlow == .confirming ? 360 : 220)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .zIndex(6)
            }
            
            // only intercept taps while inline search is open
            if vm.passengerFlow == .searching && showingInlineSearch {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        // close inline search when tapping outside
                        showingInlineSearch = false
                        inlineFieldIsFocused = false
                        inlineQuery = ""
                        inlineCompleter.update(query: "")
                        cancelInlineSearch()
                    }
                    .zIndex(1)
            }
            
            // Transparent drag layer to detect manual map interaction and disable tracking
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 5)
                    .onChanged { _ in
                        if isTrackingUser {
                            isTrackingUser = false
                        }
                    }
                )
                .allowsHitTesting(false)
            
            // passenger / driver controls
            VStack { Spacer()
                HStack(spacing: 12) {
                    if role.lowercased().contains("passenger") {
                        passengerControls
                    } else {
                        DriverControls(
                            isOnline: vm.isOnline,
                            activeDriverCount: vm.drivers.count,
                            onGoOnline: handleGoOnlineTapped
                        )
                    }
                }
                .padding()
            }
            
            if role.lowercased().contains("driver"),
               !vm.rideAccepted,
               !vm.incomingRideRequests.isEmpty {
                VStack {
                    Spacer()
                    DriverIncomingRequestsPanel(
                        requests: vm.incomingRideRequests,
                        onAccept: vm.acceptIncomingRide
                    )
                        .padding(.horizontal)
                        .padding(.bottom, 96)
                }
            }
            
            if role.lowercased().contains("driver"), vm.rideAccepted, let active = vm.activeRideRow {
                VStack {
                    Spacer()
                    DriverActiveRidePanel(
                        active: active,
                        boardingCodeVerified: vm.boardingCodeVerified,
                        onArrive: { rideId in
                            guard let driverId = SavariSessionStore.authToken else { return }
                            Task {
                                let ok = await vm.driverArrived(rideId: rideId, driverId: driverId)
                                if !ok {
                                    SavariLog.debug("arrive failed")
                                }
                            }
                        },
                        onEnterCode: {
                            vm.driverBoardingCodeEntry = ""
                            vm.driverFlow = .awaitingOTP
                        },
                        onStartRide: { rideId in
                            Task {
                                let ok = await vm.startRideNow(rideId: rideId)
                                if !ok {
                                    SavariLog.debug("start failed")
                                }
                            }
                        },
                        onEndRide: { rideId in
                            Task {
                                let ok = await vm.endRideNow(rideId: rideId)
                                if !ok {
                                    SavariLog.debug("end failed")
                                }
                            }
                        }
                    )
                    .padding(.bottom, 80)
                    .padding(.horizontal)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            topBar
                .allowsHitTesting(vm.passengerFlow != .matching)
                .opacity(vm.passengerFlow == .matching ? 0.6 : 1)
                .padding(.horizontal)
                .padding(.top, 6)
        }
        .onAppear {
            GPSLocationPusher.shared.start()
            Task {
                // start view model realtime subscriptions
                await vm.start()
            }
            
            if let lastCoordinate = SavariSessionStore.lastCoordinate {
                mapPosition = .region(MKCoordinateRegion(center: lastCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            } else {
                mapPosition = .automatic
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !didCenterToUser {
                    if let first = vm.drivers.first {
                        mapPosition = .region(MKCoordinateRegion(center: first.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
                    }
                }
            }
        }
        .onDisappear { vm.stopAll() }
    }
    
    private var topBar: some View {
        DashboardTopBar(
            role: role,
            vm: vm,
            inlineCompleter: inlineCompleter,
            destinationText: $destinationText,
            showingInlineSearch: $showingInlineSearch,
            inlineQuery: $inlineQuery,
            inlineChosenMapItem: $inlineChosenMapItem,
            showMapPickerSheet: $showMapPickerSheet,
            inlineFieldIsFocused: $inlineFieldIsFocused,
            isSigningOut: isSigningOut,
            onSignOut: { Task { await signOut() } },
            onInlineQueryChanged: scheduleInlineSearch,
            onClearInlineQuery: clearInlineQuery,
            onMapPickerDismiss: handleMapPickerDismiss,
            onMapItemPicked: handleMapItemPicked,
            onCancelPassengerFlow: cancelPassengerFlow,
            onCompletionSelected: { item in Task { await handleInlineSelection(item: item) } }
        )
    }

    @MainActor
    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true

        vm.stopOnline()
        vm.stopAll()
        await SupabaseManager.shared.signOut()

        authToken = nil
        lastRole = nil
        isOnboardingComplete = false

        SavariSessionStore.clearLastCoordinate()
        let defaults = UserDefaults.standard
        [
            "savariSmokeSelfAcceptStatus",
            "savariSmokeSelfAcceptRideId",
            "savariSmokeSelfAcceptAccepted",
            "savariSmokeSelfAcceptError"
        ].forEach { defaults.removeObject(forKey: $0) }

        isSigningOut = false
    }
    
    // MARK: - Passenger controls
    private var passengerControls: some View {
        HStack(spacing: 12) {
            
             if vm.rideAccepted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Driver on the way", systemImage: "location")
                    if vm.rideAccepted, let eta = vm.assignedDriverETASeconds {
                        Text("Driver ETA \(eta/60)m")
                    }
                }
                .padding(10)
                .background(Material.ultraThin)
                .cornerRadius(12)
            }
            
            if let code = vm.activeRideRow?["boarding_code"] as? String, role.lowercased().contains("passenger") {
                
                VStack {
                    BoardingCodeView(
                        code: code,
                        ttlSeconds: vm.activeRideRow?["boarding_code_ttl"] as? Int
                    )
                    
                    Button("I've boarded") {
                        // removed: vm.showRideSheet = false
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                }
                .padding(.top, 12)
            } else {
                // existing small order UI
            }
        }
    }
    
    private func handleGoOnlineTapped() {
        if !vm.isOnline, let driverId = SavariSessionStore.authToken {
            vm.goOnline(driverId: driverId)
        }
        SavariLog.debug("[UI] Go Online button tapped; vm.rideAccepted = \(vm.rideAccepted)")
        if vm.rideAccepted {
            return
        }
        if let driverId = SavariSessionStore.authToken, !driverId.isEmpty {
            vm.goOnline(driverId: driverId)
        } else {
            SavariLog.debug("[UI] No authToken found in UserDefaults; goOnline won't run")
        }
    }
    
    private func cancelInlineSearch() {
        inlineSearchTask?.cancel()
        inlineSearchTask = nil
        
        showingInlineSearch = false
        inlineFieldIsFocused = false
        inlineQuery = ""
        inlineCompleter.update(query: "")
    }

    private func scheduleInlineSearch(_ query: String) {
        inlineSearchTask?.cancel()
        if let pickup = GPSLocationPusher.shared.current {
            inlineCompleter.region = MKCoordinateRegion(
                center: pickup,
                span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
            )
        }

        inlineSearchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            inlineCompleter.update(query: query)
        }
    }

    private func clearInlineQuery() {
        inlineQuery = ""
        inlineCompleter.update(query: "")
    }

    private func handleMapPickerDismiss() {
        if vm.passengerFlow == .searching {
            vm.passengerFlow = .idle
        }
        cancelInlineSearch()
    }

    private func handleMapItemPicked(_ item: MKMapItem) {
        Task {
            await handleInlineSelection(
                item: .init(
                    title: item.name ?? item.placemark.title ?? "Picked",
                    subtitle: item.placemark.title ?? "",
                    mapItem: item,
                    completion: nil
                )
            )
        }
    }
    
    // MARK: - Passenger flow helper (sequence)
    private func performPassengerRequestFlow() async {
        guard
            let pickup = pickupCoordinate,
            let dest = destCoordinate,
            let passengerId = SavariSessionStore.authToken
        else { return }

        let finalTransport = vm.chosenTransportOption ?? "Auto"
        let finalFare = vm.selectedRide.amount
        let distanceMeters = vm.selectedRide.distanceMeters ?? 0
        let etaSeconds = vm.selectedRide.etaSeconds

        if let rideId = await RideService.shared.createRideRequest(
            passengerId: passengerId,
            pickupLat: pickup.latitude,
            pickupLon: pickup.longitude,
            dropLat: dest.latitude,
            dropLon: dest.longitude,
            vehicleType: finalTransport,
            estimatedFare: finalFare,
            estimatedDistanceMeters: distanceMeters,
            estimatedETASecs: etaSeconds
        ) {
            await MainActor.run {
                vm.selectedRide.orderID = rideId
                vm.rideRequested = true
                vm.passengerFlow = .matching
            }

            await vm.subscribeToMyRide(rideId: rideId)
        }
    }
    
    // REPLACE your current handleInlineSelection(...) with this
    private func handleInlineSelection(item: LocationCompleter.CompletionItem) async {
        // 1) resolve mapItem
        var resolvedMapItem: MKMapItem? = nil
        
        if let mapItem = item.mapItem {
            resolvedMapItem = mapItem
        } else if let comp = item.completion {
            let req = MKLocalSearch.Request(completion: comp)
            let search = MKLocalSearch(request: req)
            do {
                let resp = try await search.start()
                resolvedMapItem = resp.mapItems.first
            } catch {
                SavariLog.debug("[Inline] completion -> search.start error:", error.localizedDescription)
            }
        }
        
        // fallback natural-language search
        if resolvedMapItem == nil {
            let q = "\(item.title) \(item.subtitle)".trimmingCharacters(in: .whitespacesAndNewlines)
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q
            if let r = inlineCompleter.region { req.region = r }
            let s = MKLocalSearch(request: req)
            if let resp = try? await s.start(), let mi = resp.mapItems.first {
                resolvedMapItem = mi
            }
        }
        
        guard let mi = resolvedMapItem else {
            SavariLog.debug("[Inline] couldn't resolve mapItem for selection")
            return
        }
        
        // 2) set destination text & chosen map item
        await MainActor.run {
            inlineChosenMapItem = mi
            destCoordinate = mi.placemark.coordinate
            destinationText = mi.name ?? "\(mi.placemark.title ?? "")"
            showingInlineSearch = false
            inlineQuery = ""
            inlineCompleter.update(query: "")
            vm.passengerFlow = .preview
            showingInlineSearch = false
            inlineFieldIsFocused = false
        }
        
        // 3) compute route & ETA from current pickup -> destination and update VM + map
        if let pickup = GPSLocationPusher.shared.current {
            do {
                let routeResult = try await RoutingService.shared.calculateRoute(from: pickup, to: mi.placemark.coordinate)
                
                await MainActor.run {
                    // update VM (so other UI pieces read it)
                    vm.selectedRide.routeCoordinates = routeResult.coordinates
                    vm.selectedRide.distanceMeters = routeResult.distanceMeters
                    vm.selectedRide.etaSeconds = Int(routeResult.expectedTravelTime)
                    vm.selectedRide.etaDate = RoutingService.etaDate(from: routeResult.expectedTravelTime)
                    vm.updateFareEstimates(distanceMeters: routeResult.distanceMeters)
                    
                    // set pickup & dest markers shown on the map
                    pickupCoordinate = pickup
                    destCoordinate = mi.placemark.coordinate
                    
                    // animate camera to fit both points with padding using helper
                    let region = MapCameraHelpers.regionFitting([pickup, mi.placemark.coordinate])
                    withAnimation(.easeInOut) {
                        mapPosition = .region(region)
                    }
                }
            } catch {
                SavariLog.debug("[Inline] routing failed:", error.localizedDescription)
                // fallback: simply center on destination
                await MainActor.run {
                    mapPosition = .region(MKCoordinateRegion(center: mi.placemark.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                    pickupCoordinate = GPSLocationPusher.shared.current
                    destCoordinate = mi.placemark.coordinate
                }
            }
        } else {
            // no pickup available — just center on destination
            await MainActor.run {
                mapPosition = .region(MKCoordinateRegion(center: mi.placemark.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                destCoordinate = mi.placemark.coordinate
            }
        }
    }
    
    private func cancelPassengerFlow() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        
        // 1. Reset flow
        vm.passengerFlow = .idle
        
        // 2. Clear search
        cancelInlineSearch()
        destinationText = ""
        inlineChosenMapItem = nil
        
        // 3. Clear map
        pickupCoordinate = nil
        destCoordinate = nil
        vm.selectedRide.routeCoordinates = []
        
        // 4. Clear ride preview
        vm.selectedRide.distanceMeters = nil
        vm.selectedRide.etaSeconds = 0
        vm.selectedRide.amount = 0
        vm.chosenTransportOption = nil
        
        // 5. Recenter map
        if let coord = GPSLocationPusher.shared.current {
            withAnimation(.easeInOut) {
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
        }
    }
}
