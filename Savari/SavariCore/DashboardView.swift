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
            DashboardMapLayer(
                role: role,
                vm: vm,
                mapPosition: $mapPosition,
                didCenterToUser: $didCenterToUser,
                isTrackingUser: $isTrackingUser,
                pickupCoordinate: pickupCoordinate,
                destCoordinate: destCoordinate
            )
            DashboardPassengerRideOverlayLayer(
                vm: vm,
                onUsePreview: {
                    withAnimation(.spring()) {
                        vm.passengerFlow = .confirming
                    }
                },
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
                    if isPassenger {
                        DashboardPassengerControls(vm: vm)
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
            
            if isDriver {
                DashboardDriverOverlayLayer(vm: vm)
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

    private var isPassenger: Bool {
        role.lowercased().contains("passenger")
    }

    private var isDriver: Bool {
        role.lowercased().contains("driver")
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
    
    private func handleGoOnlineTapped() {
        SavariLog.debug("[UI] Go Online button tapped; vm.rideAccepted = \(vm.rideAccepted)")
        if vm.rideAccepted {
            return
        }
        if let driverId = SavariSessionStore.authToken, !driverId.isEmpty {
            if !vm.isOnline {
                vm.goOnline(driverId: driverId)
            }
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
    
    private func handleInlineSelection(item: LocationCompleter.CompletionItem) async {
        guard let selection = await DashboardDestinationSelectionResolver.resolve(
            item: item,
            searchRegion: inlineCompleter.region,
            pickup: GPSLocationPusher.shared.current
        ) else {
            return
        }

        await MainActor.run {
            inlineChosenMapItem = selection.mapItem
            destinationText = selection.destinationText
            showingInlineSearch = false
            inlineQuery = ""
            inlineCompleter.update(query: "")
            vm.passengerFlow = .preview
            inlineFieldIsFocused = false

            pickupCoordinate = selection.pickupCoordinate
            destCoordinate = selection.destinationCoordinate

            if let route = selection.route {
                vm.selectedRide.routeCoordinates = route.coordinates
                vm.selectedRide.distanceMeters = route.distanceMeters
                vm.selectedRide.etaSeconds = route.etaSeconds
                vm.selectedRide.etaDate = route.etaDate
                vm.updateFareEstimates(distanceMeters: route.distanceMeters)
            }

            withAnimation(.easeInOut) {
                mapPosition = .region(selection.mapRegion)
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
