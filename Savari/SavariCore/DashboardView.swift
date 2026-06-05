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
    @AppStorage("authToken") private var authToken: String?
    @AppStorage("lastRole") private var lastRole: String?
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete: Bool = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var didCenterToUser: Bool = false
    @State private var isSigningOut: Bool = false
    
    // passenger UI state
    @State private var destinationText: String = ""
    // Removed @State private var chosenTransport
    
    @State private var followAssignedDriver: Bool = true
    @State private var showRouteOverlay: Bool = true
    
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
    
    // keep a reference if you use MKLocalSearch directly (optional)
    @State private var activeMKSearch: MKLocalSearch? = nil
    
    @FocusState private var inlineFieldIsFocused: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let searchBarHeight: CGFloat = 44
    
    init(role: String) {
        self.role = role
        let route = Route(start: CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090),
                          end: CLLocationCoordinate2D(latitude: 28.62, longitude: 77.225))
        _vm = StateObject(wrappedValue: DashboardViewModelRealtime(route: route, role: role))
    }
    
    var body: some View {
        ZStack {
            // --- Map (only MapContent inside builder) ---
            Map(position: $mapPosition) {
                ForEach(vm.drivers) { driver in
                    Annotation("", coordinate: driver.coordinate) {
                        DriverAnnotationView(driver: driver)
                            .accessibilityLabel(driver.name)
                            .onTapGesture {
                                withAnimation {
                                    mapPosition = .region(
                                        MKCoordinateRegion(center: driver.coordinate,
                                                           span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
                                    )
                                }
                            }
                    }
                }
                
                // <-- ADD HERE: native polyline overlay as MapContent
                if showRouteOverlay && !vm.selectedRide.routeCoordinates.isEmpty {
                    MapPolyline(coordinates: vm.selectedRide.routeCoordinates)
                        .stroke(Color.blue, lineWidth: 4)
                }
                
                // Passenger-only markers
                if role.lowercased().contains("passenger") {
                    // pickup marker
                    if let pickup = pickupCoordinate {
                        Annotation("", coordinate: pickup) {
                            VStack(spacing: 4) {
                                Image(systemName: "circle.fill").resizable().frame(width: 18, height: 18).foregroundColor(.blue)
                                Text("You").font(.caption2).padding(6).background(Material.ultraThin).cornerRadius(6)
                            }
                            .accessibilityLabel("Pickup")
                        }
                    }
                    
                    // destination marker
                    if let dest = destCoordinate {
                        Annotation("", coordinate: dest) {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle().fill(Color.red).frame(width: 34, height: 34).shadow(radius: 3)
                                    Image(systemName: "mappin").foregroundColor(.white)
                                }
                                Text("Destination").font(.caption2).padding(6).background(Material.ultraThin).cornerRadius(6)
                            }
                            .accessibilityLabel("Destination")
                        }
                    }
                }
                
                // live user location marker (follows GPSLocationPusher.shared.current)
                if let userCoord = GPSLocationPusher.shared.current {
                    Annotation("", coordinate: userCoord) {
                        VStack(spacing: 4) {
                            // Apple-like circular marker with subtle halo + small user icon
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: 40, height: 40)
                                    .shadow(radius: 6)
                                Circle()
                                    .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                                    .frame(width: 48, height: 48)
                                Image(systemName: "person.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            Text("You").font(.caption2).padding(6).background(Material.ultraThin).cornerRadius(6)
                        }
                        .accessibilityLabel("You")
                    }
                }
                
                // show assigned driver distinctly
                if let ad = vm.assignedDriver, role.lowercased().contains("passenger") {
                    Annotation("", coordinate: ad.coordinate) {
                        VStack {
                            ZStack {
                                Circle().fill(Color.green).frame(width: 48, height: 48).shadow(radius: 3)
                                Image(systemName: "car.fill").foregroundColor(.white)
                            }
                            Text("Driver").font(.caption2).padding(6).background(Material.ultraThin).cornerRadius(6)
                        }
                        .fixedSize()
                        .accessibilityLabel("Assigned driver")
                    }
                }
                
                // Driver: show passenger pickup pin when on a job
                if role.lowercased().contains("driver"),
                   let active = vm.activeRideRow,
                   let plat = active["pickup_lat"] as? Double,
                   let plon = active["pickup_lon"] as? Double {
                    let pickup = CLLocationCoordinate2D(latitude: plat, longitude: plon)
                    Annotation("", coordinate: pickup) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(Color.blue).frame(width: 34, height: 34).shadow(radius: 3)
                                Image(systemName: "person.fill").foregroundColor(.white)
                            }
                            Text("Pickup").font(.caption2).padding(6).background(Material.ultraThin).cornerRadius(6)
                        }
                        .accessibilityLabel("Pickup")
                    }
                }
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
            // Put this near the end of your view modifiers in `body` (e.g. after .onReceive or inside .onAppear area)
            .onChange(of: destCoordinate.map { CGPoint(x: $0.latitude, y: $0.longitude) }) { _ in
                Task {
                    // only compute when both pickup (user) and dest exist
                    guard let dest = destCoordinate else { return }
                    // prefer pickupCoordinate if set, else current GPS
                    let pickup = pickupCoordinate ?? GPSLocationPusher.shared.current
                    guard let pickupCoord = pickup else { return }
                    
                    do {
                        let routeResult = try await RoutingService.shared.calculateRoute(from: pickupCoord, to: dest)
                        await MainActor.run {
                            // update VM + map overlay + local coords
                            vm.selectedRide.routeCoordinates = routeResult.coordinates
                            vm.selectedRide.distanceMeters = routeResult.distanceMeters
                            vm.selectedRide.etaSeconds = Int(routeResult.expectedTravelTime)
                            vm.selectedRide.etaDate = RoutingService.etaDate(from: routeResult.expectedTravelTime)
                            vm.updateFareEstimates(distanceMeters: routeResult.distanceMeters)
                            pickupCoordinate = pickupCoord
                            destCoordinate = dest
                            
                            // animate camera to fit both points with padding using helper
                            let region = MapCameraHelpers.regionFitting([pickupCoord, dest])
                            withAnimation(.easeInOut) {
                                mapPosition = .region(region)
                            }
                        }
                    } catch {
                        // fallback: set basic fields from straight-line estimate
                        await MainActor.run {
                            let a = CLLocation(latitude: pickupCoord.latitude, longitude: pickupCoord.longitude)
                            let b = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
                            let dist = a.distance(from: b)
                            vm.selectedRide.distanceMeters = dist
                            vm.selectedRide.etaSeconds = Int(dist / 8.0) // fallback speed ~8 m/s
                            pickupCoordinate = pickupCoord
                            destCoordinate = dest
                            withAnimation(.easeInOut) {
                                mapPosition = .region(MKCoordinateRegion(center: dest, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
                            }
                        }
                    }
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
                    if role.lowercased().contains("passenger") { passengerControls } else { driverControls }
                }
                .padding()
            }
            
            if role.lowercased().contains("driver"),
               !vm.rideAccepted,
               !vm.incomingRideRequests.isEmpty {
                VStack {
                    Spacer()
                    driverIncomingRequestsPanel
                        .padding(.horizontal)
                        .padding(.bottom, 96)
                }
            }
            
            // Driver active-ride panel (shows once driver accepted)
            if role.lowercased().contains("driver"), vm.rideAccepted, let active = vm.activeRideRow {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Ride: \(active["id"] as? String ?? "—")").font(.headline)
                                if let pax = active["passenger_id"] as? String { Text("Passenger: \(String(pax.prefix(6)))").font(.caption) }
                                Text("Pickup").font(.caption2)
                                if let plat = active["pickup_lat"] as? Double, let plon = active["pickup_lon"] as? Double {
                                    Text(String(format: "%.5f, %.5f", plat, plon)).font(.caption2)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Fare ₹\(fareString(for: active))").bold()
                                Text("Status: \(active["status"] as? String ?? "—")").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(spacing: 12) {
                            Button("Navigate") {
                                // open Apple Maps to pickup
                                if let plat = active["pickup_lat"] as? Double, let plon = active["pickup_lon"] as? Double {
                                    let coord = CLLocationCoordinate2D(latitude: plat, longitude: plon)
                                    let placemark = MKPlacemark(coordinate: coord)
                                    let mapItem = MKMapItem(placemark: placemark)
                                    mapItem.name = "Pickup"
                                    mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                                }
                            }
                            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                            
                            Button(action: {
                                // mark arrived
                                if let id = active["id"] as? String, let driverId = UserDefaults.standard.string(forKey: "authToken") {
                                    Task {
                                        let ok = await vm.driverArrived(rideId: id, driverId: driverId)
                                        if !ok { SavariLog.debug("arrive failed") }
                                    }
                                }
                            }) {
                                Text("Arrive")
                            }
                            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                            
                            // OTP sheet trigger: changed to driverFlow
                            Button("Enter Code") {
                                vm.driverBoardingCodeEntry = ""
                                vm.driverFlow = .awaitingOTP
                            }
                            .buttonStyle(LiquidGlassButtonStyle())
                        }
                        
                        // Show small control row when OTP verified or boarded
                        if vm.boardingCodeVerified || (active["status"] as? String) == "boarded" || (active["status"] as? String) == "in_progress" {
                            HStack(spacing: 12) {
                                Button("Start Ride") {
                                    if let id = active["id"] as? String {
                                        Task {
                                            let ok = await vm.startRideNow(rideId: id)
                                            if !ok { SavariLog.debug("start failed") }
                                        }
                                    }
                                }.disabled((active["status"] as? String) == "in_progress")
                                    .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                                
                                Button("End Ride & Unlock Fare") {
                                    if let id = active["id"] as? String {
                                        Task {
                                            let ok = await vm.endRideNow(rideId: id)
                                            if !ok { SavariLog.debug("end failed") }
                                        }
                                    }
                                }
                                .buttonStyle(LiquidGlassButtonStyle())
                            }
                        }
                    }
                    .padding()
                    .background(Material.ultraThin)
                    .cornerRadius(16)
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
            
            if let lastLat = UserDefaults.standard.value(forKey: "lastLat") as? Double,
               let lastLon = UserDefaults.standard.value(forKey: "lastLon") as? Double,
               lastLat != 0 {
                mapPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lastLat, longitude: lastLon), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
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
    
    // create a small computed property for the top bar (includes dropdown)
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Savari.").font(.largeTitle.monospacedDigit()).foregroundColor(.primary)
                Spacer()
                Circle()
                    .fill(vm.isRealtimeActive ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 12, height: 12)

                Menu {
                    Button(role: .destructive) {
                        Task { await signOut() }
                    } label: {
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
            
            // the search pill and map button
            HStack(spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                    Group {
                        if role.lowercased().contains("passenger") {
                            if vm.passengerFlow == .searching && showingInlineSearch {
                                TextField("Where to?", text: $inlineQuery)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 10)
                                    .padding(.trailing, 6)
                                    .focused($inlineFieldIsFocused)
                                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { inlineFieldIsFocused = true } }
                                    .onChange(of: inlineQuery) { new in
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
                                            inlineCompleter.update(query: new)
                                        }
                                    }
                                    .onSubmit {
                                        if let first = inlineCompleter.completions.first { Task { await handleInlineSelection(item: first) } }
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
                    }
                    
                    if vm.passengerFlow == .searching && showingInlineSearch && !inlineQuery.isEmpty {
                        Button(action: {
                            inlineQuery = ""
                            inlineCompleter.update(query: "")
                        }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
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
                
                Button(action: {
                    if vm.passengerFlow == .idle {
                        vm.passengerFlow = .searching
                    }
                    showingInlineSearch = false
                    inlineQuery = ""
                    inlineCompleter.update(query: "")
                    showMapPickerSheet = true
                }) {
                    Image(systemName: "map")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(10)
                        .background(Material.ultraThin)
                        .cornerRadius(10)
                }
                .sheet(isPresented: $showMapPickerSheet, onDismiss: {
                    if vm.passengerFlow == .searching {
                            vm.passengerFlow = .idle
                        }
                        showingInlineSearch = false
                        inlineQuery = ""
                        inlineCompleter.update(query: "")
                    }) {
                    MapPickerView(selectedItem: $inlineChosenMapItem) { item in
                        Task {
                            await handleInlineSelection(
                                item: .init(title: item.name ?? item.placemark.title ?? "Picked",
                                            subtitle: item.placemark.title ?? "",
                                            mapItem: item,
                                            completion: nil)
                            )
                        }
                    }
                }
                
                // after the map button, show Cancel when inline is active
                if role.lowercased().contains("passenger"),
                   vm.passengerFlow == .searching
                   || vm.passengerFlow == .preview
                   || vm.passengerFlow == .confirming {
                    Button("Cancel") {
                        // Fully clear inline search UI and any temporary destination state
                        cancelPassengerFlow()
                        cancelInlineSearch()
                        destinationText = ""
                        inlineChosenMapItem = nil
                        destCoordinate = nil
                        vm.selectedRide.routeCoordinates = []
                        pickupCoordinate = nil
                    }
                    .foregroundColor(.primary)
                    .padding(.leading, 6)
                }
            }
            
            // ---- RESULTS DROPDOWN (restore this so search results are visible) ----
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
                                    Button(action: { Task { await handleInlineSelection(item: item) } }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title).font(.body)
                                            if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundColor(.secondary) }
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 10)
                                    }
                                    Divider().padding(.leading)
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

        let defaults = UserDefaults.standard
        [
            "lastLat",
            "lastLon",
            "savariSmokeSelfAcceptStatus",
            "savariSmokeSelfAcceptRideId",
            "savariSmokeSelfAcceptAccepted",
            "savariSmokeSelfAcceptError"
        ].forEach { defaults.removeObject(forKey: $0) }

        isSigningOut = false
    }
    
    // MARK: - Distance + ETA floating box used in Dashboard (bottom-centered)
    private struct DistanceETABox: View {
        let distanceMeters: CLLocationDistance?
        let etaSeconds: TimeInterval?
        var onUse: () -> Void

        @State private var pressed = false

        var body: some View {
            HStack(spacing: 18) {

                // 📍 Distance + ETA (slightly left weighted)
                VStack(alignment: .leading, spacing: 4) {
                    if let d = distanceMeters {
                        Text(RideFormat.distance(d))
                            .font(.system(size: 16, weight: .semibold))
                    } else {
                        Text("—")
                            .font(.system(size: 16, weight: .semibold))
                    }

                    if let eta = etaSeconds, eta > 0 {
                        Text("~\(Int(eta / 60)) min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 4)

                Spacer()

                // ➡️ Continue pill
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onUse()
                }) {
                    HStack(spacing: 10) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))

                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                }
                .buttonStyle(LiquidGlassButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(
                                pressed
                                ? Color.white.opacity(0.22)
                                : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: pressed)
            .onLongPressGesture(minimumDuration: 0.01, pressing: { isPressing in
                pressed = isPressing
            }, perform: {})
            .padding(.horizontal)
        }
    }
    
    struct RideFlowCard: View {
        let flow: PassengerFlowState
        let vm: DashboardViewModelRealtime
        let onConfirm: () -> Void
        let onCancel: () -> Void

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.white.opacity(0.08))
                    )

                content
                    .padding(24)
            }
            .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: flow)
        }

        @ViewBuilder
        private var content: some View {
            switch flow {

            case .confirming:
                ConfirmRideSheet(vm: vm, onConfirm: onConfirm)

            case .matching:
                    RideStatusCard(
                        state: .matching,
                        onCancel: onCancel,
                        onContact: {}
                    )

            case .accepted:
                    if let driver = vm.assignedDriver {
                        RideStatusCard(
                            state: .accepted(
                                driver: driver,
                                etaSeconds: vm.assignedDriverETASeconds ?? 0
                            ),
                            onCancel: onCancel,
                            onContact: {
                                // later: call / chat
                            }
                        )
                    } else {
                                // safety fallback
                                RideStatusCard(
                                    state: .matching,
                                    onCancel: onCancel,
                                    onContact: {}
                                )
                            }

            default:
                EmptyView()
            }
        }
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
    
    // MARK: - Driver controls
    private var driverControls: some View {
        HStack(spacing: 12) {
            Button(action: {
                if !vm.isOnline, let driverId = UserDefaults.standard.string(forKey: "authToken") {
                    vm.goOnline(driverId: driverId)
                }
                SavariLog.debug("[UI] Go Online button tapped; vm.rideAccepted = \(vm.rideAccepted)")
                if vm.rideAccepted {
                    // already on a ride / on duty
                } else {
                    if let driverId = UserDefaults.standard.string(forKey: "authToken"), !driverId.isEmpty {
                        vm.goOnline(driverId: driverId)
                    } else {
                        SavariLog.debug("[UI] No authToken found in UserDefaults; goOnline won't run")
                    }
                }
            }) {
                HStack { Image(systemName: "checkmark.circle"); Text(vm.isOnline ? "Online" : "Go Online") }
            }
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
            .frame(maxWidth: 220)
            .disabled(vm.isOnline)
            
            Spacer().frame(width: 8)
            VStack(alignment: .trailing) { Text("Active drivers: \(vm.drivers.count)").font(.caption).foregroundColor(.secondary) }
        }
    }

    private var driverIncomingRequestsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ride requests", systemImage: "bell.badge.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(vm.incomingRideRequests.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
            }

            ForEach(Array(vm.incomingRideRequests.prefix(3).enumerated()), id: \.offset) { _, ride in
                driverIncomingRequestRow(ride)
            }
        }
        .padding(14)
        .background(Material.ultraThin)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
    }

    private func driverIncomingRequestRow(_ ride: [String: Any]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ride \(rideShortId(ride))")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(rideDistanceString(for: ride)) • \(rideVehicleType(for: ride))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("₹\(fareString(for: ride))")
                .font(.system(size: 14, weight: .semibold))

            Button("Accept") {
                vm.acceptIncomingRide(ride)
            }
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
        }
        .padding(10)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(12)
    }
    
    private func cancelInlineSearch() {
        // 1) Cancel any running Swift concurrency Task
        inlineSearchTask?.cancel()
        inlineSearchTask = nil
        
        // 2) Cancel any MKLocalSearch in-flight (if you keep a reference)
        activeMKSearch?.cancel()
        activeMKSearch = nil
        
        // 3) Clear UI state
        showingInlineSearch = false
        inlineFieldIsFocused = false
        inlineQuery = ""
        inlineCompleter.update(query: "")    // tell completer to clear results
    }
    
    // MARK: - Passenger flow helper (sequence)
    private func performPassengerRequestFlow() async {
        guard
            let pickup = pickupCoordinate,
            let dest = destCoordinate,
            let passengerId = UserDefaults.standard.string(forKey: "authToken")
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
    
    // very simple fare estimator – replace with your pricing logic
    private func estimateFare(distanceMeters: CLLocationDistance, transport: String) -> Double {
        let km = distanceMeters / 1000.0
        switch transport {
        case "Bike": return max(30.0, 10.0 + km * 8.0)
        default: return max(50.0, 20.0 + km * 12.0)
        }
    }
    
    // New helper: format fare string from activeRideRow dictionary
    private func fareString(for active: [String: Any]) -> String {
        if let d = doubleValue(active["estimated_fare"]) {
            return String(format: "%.2f", d)
        }
        if let d = active["fare"] as? Double {
            return String(format: "%.2f", d)
        }
        if let s = active["fare"] as? String, let d = Double(s) {
            return String(format: "%.2f", d)
        }
        return String(format: "%.2f", 0.0)
    }

    private func rideShortId(_ ride: [String: Any]) -> String {
        guard let id = ride["id"] as? String, !id.isEmpty else { return "NEW" }
        return String(id.prefix(8)).uppercased()
    }

    private func rideVehicleType(for ride: [String: Any]) -> String {
        (ride["vehicle_type"] as? String) ?? "Ride"
    }

    private func rideDistanceString(for ride: [String: Any]) -> String {
        guard let meters = doubleValue(ride["estimated_distance_meters"]), meters > 0 else {
            return "Distance pending"
        }
        return String(format: "%.1f km", meters / 1000.0)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
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

// MARK: - ConfirmRideSheet
struct ConfirmRideSheet: View {
    @ObservedObject var vm: DashboardViewModelRealtime
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {

            // Drag indicator — Apple exact
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Title
            Text("Choose your ride")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 4)

            // Transport options
            HStack(spacing: 12) {
                TransportCard(
                    title: "Auto",
                    fare: vm.fareAuto,
                    isSelected: vm.chosenTransportOption == "Auto"
                ) {
                    vm.chosenTransportOption = "Auto"
                    vm.selectedRide.amount = vm.fareAuto ?? vm.selectedRide.amount
                }

                TransportCard(
                    title: "Bike",
                    fare: vm.fareBike,
                    isSelected: vm.chosenTransportOption == "Bike"
                ) {
                    vm.chosenTransportOption = "Bike"
                    vm.selectedRide.amount = vm.fareBike ?? vm.selectedRide.amount
                }
            }
            .padding(.top, 4)

            // Price emphasis (Apple Pay style)
            if vm.selectedRide.amount > 0 {
                Text("₹\(Int(vm.selectedRide.amount))")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.top, 4)
            }

            // Distance / ETA (secondary metadata)
            HStack(spacing: 12) {
                if let d = vm.selectedRide.distanceMeters {
                    Text(String(format: "%.1f km", d / 1000))
                }
                if vm.selectedRide.etaSeconds > 0 {
                    Text("~\(vm.selectedRide.etaSeconds / 60)m")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            let canConfirm =
                vm.chosenTransportOption != nil &&
                vm.selectedRide.amount > 0

            // Confirm Ride — Apple Pay primary action
            Button(action: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConfirm()
            }) {
                Text("Confirm Ride")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                    .foregroundColor(Color(UIColor.systemBackground))
            }
            .disabled(!canConfirm)
            .opacity(canConfirm ? 1 : 0.4)
            .padding(.top, 8)

        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// small helpers
@ViewBuilder
private func fareHeaderItem(title: String, fare: Double?, isSelected: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.caption)
        if let f = fare {
            Text("₹\(Int(f))").font(.headline)
        } else {
            Text("—").font(.headline)
        }
    }
    .padding(16)
    .background(.ultraThinMaterial)
    .cornerRadius(22)
    .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
    .padding(.horizontal, 12)
}

// TransportCard small component
struct TransportCard: View {
    let title: String
    let fare: Double?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap()
        }) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                if let f = fare {
                    Text("₹\(Int(f))")
                        .font(.system(size: 20, weight: .bold))
                } else {
                    Text("—")
                        .font(.headline)
                }
            }
            .frame(width: 144, height: 96)
            .background(
                ZStack {
                    // Base fill with subtle gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            isSelected
                            ? LinearGradient(colors: [Color.primary.opacity(0.96), Color.primary.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(.secondarySystemBackground), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    // Inner highlight for glassy look
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                        .blendMode(.overlay)
                }
            )
            .overlay(
                // Subtle sheen when selected
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.12) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.28 : 0.16), radius: isSelected ? 18 : 12, x: 0, y: isSelected ? 10 : 8)
            .shadow(color: Color.white.opacity(0.06), radius: 1, x: 0, y: 1)
            .foregroundColor(
                isSelected
                ? Color(UIColor.systemBackground)
                : Color.primary.opacity(0.92)
            )
            .scaleEffect(isSelected ? 1.01 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSelected)
        }
        .buttonStyle(LiquidGlassButtonStyle())
    }
}

struct RideStatusCard: View {

    enum RideStatus {
        case matching
        case accepted(driver: Driver, etaSeconds: Int)
    }

    let state: RideStatus
    let onCancel: () -> Void
    let onContact: () -> Void

    @State private var animate = false

    var body: some View {
        VStack(spacing: 16) {

            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)

            switch state {
            case .matching:
                matchingContent

            case .accepted(let driver, let eta):
                acceptedContent(driver: driver, eta: eta)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(Color.white.opacity(0.08))
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        .onAppear { animate = true }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: animate)
    }

    // MARK: - Matching UI
    private var matchingContent: some View {
        VStack(spacing: 12) {

            Text("Finding your ride")
                .font(.system(size: 17, weight: .semibold))

            Text("Searching nearby drivers")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 0.6 : 1)
                        .opacity(animate ? 0.25 : 1)
                        .animation(
                            .easeInOut(duration: 0.9)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: animate
                        )
                }
            }

            Button("Cancel Request", action: onCancel)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule()
                        .stroke(Color.primary.opacity(0.18))
                )
        }
    }

    // MARK: - Accepted UI
    private func acceptedContent(driver: Driver, eta: Int) -> some View {
        VStack(spacing: 14) {

            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)

                Text("Driver found")
                    .font(.system(size: 17, weight: .semibold))

                Text(driver.name)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Divider().opacity(0.4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ETA")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("~\(eta / 60) min")
                        .font(.system(size: 16, weight: .semibold))
                }

                Spacer()

                Button(action: onContact) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(12)
                        .background(Circle().fill(Color.primary))
                        .foregroundColor(Color(UIColor.systemBackground))
                        .buttonStyle(LiquidGlassButtonStyle(isPrimary: true))
                }
            }

            Button(role: .destructive, action: onCancel) {
                Text("Cancel Ride")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        Capsule()
                            .stroke(Color.red.opacity(0.4))
                    )
            }
            .padding(.top, 4)
        }
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isPrimary ? Color(UIColor.systemBackground) : .primary)
            .background(
                ZStack {
                    // Base glass
                    if isPrimary {
                        Capsule()
                            .fill(Color.primary.opacity(0.95))
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }

                    // Inner highlight
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(configuration.isPressed ? 0.18 : 0.28),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.18 : 0.28),
                radius: configuration.isPressed ? 8 : 14,
                y: configuration.isPressed ? 4 : 10
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - Preview
struct PolishedUI_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DashboardView(role: "Passenger").preferredColorScheme(.light)
            DashboardView(role: "Driver").preferredColorScheme(.dark)
        }
    }
}
