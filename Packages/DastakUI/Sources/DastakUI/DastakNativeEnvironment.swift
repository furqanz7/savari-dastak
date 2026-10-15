import SwiftUI

/// Decorative, offline-capable native renderer. Never owns commerce/auth state.
public struct DastakNativeEnvironment: View {
    public let place: DastakEnvironmentPlace
    private let weatherOverride: DastakEnvironmentWeather?
    private let heldEyes: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @StateObject private var weather = DastakSceneWeather.shared

    public init(place: DastakEnvironmentPlace) { self.place = place; weatherOverride = nil; heldEyes = nil }
    init(place: DastakEnvironmentPlace, weather: DastakEnvironmentWeather, heldEyes: Bool = false) {
        self.place = place; weatherOverride = weather; self.heldEyes = heldEyes
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Group {
                #if os(iOS)
                GeometryReader { geometry in
                    let reading = weatherOverride ?? weather.current(at:context.date)
                    ZStack(alignment:.top) {
                        Color(red:0.72,green:0.75,blue:0.73)
                        ZStack {
                            DastakNativeSky(weather:reading,reducedMotion:reduceMotion,
                                active:phase == .active && place == .outside)
                                .id(reading).transition(.opacity)
                        }
                            .animation(reduceMotion ? nil : .easeInOut(duration:1.2),value:reading)
                            .opacity(place == .outside ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeInOut(duration:0.85),value:place)
                        NativeEnvironmentSurface(place: place, weather: reading,
                            reducedMotion: reduceMotion, active: phase == .active, heldEyes:heldEyes,
                            portrait: geometry.size.width < geometry.size.height)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                #else
                LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
                #endif
            }
            .task(id:context.date) { if phase == .active, place == .outside { weather.resumeIfAllowed() } }
        }
        .overlay(alignment:.top) {
            // Interior controls need separation from ceiling lights. Outside,
            // leave the sky untouched: a white header wash looked like a light leak.
            LinearGradient(colors:[.black.opacity(0.55),.black.opacity(0.18),.clear],
                           startPoint:.top,endPoint:.bottom)
                .frame(height:240)
                .opacity(place == .outside ? 0 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration:0.85),value:place)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task { weather.setSceneActive(phase == .active && place == .outside) }
        .onChange(of:phase) { _,value in weather.setSceneActive(value == .active && place == .outside) }
        .onChange(of:place) { _,value in weather.setSceneActive(phase == .active && value == .outside) }
        .onDisappear { if place == .outside { weather.setSceneActive(false) } }
    }
}

#if os(iOS)
@preconcurrency import SceneKit
import UIKit

@MainActor
private struct NativeEnvironmentSurface: UIViewRepresentable {
    let place: DastakEnvironmentPlace
    let weather: DastakEnvironmentWeather
    let reducedMotion, active: Bool
    let heldEyes: Bool?
    let portrait: Bool

    func makeCoordinator() -> DastakEnvironmentScene { DastakEnvironmentScene.shared }
    func makeUIView(context: Context) -> SCNView {
        let view = NativeEnvironmentSceneView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.backgroundColor = .clear; view.isOpaque = false
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        if let surface = view as? NativeEnvironmentSceneView {
            if !active || reducedMotion { surface.tearDown() }
            let coordinator = context.coordinator
            surface.updateViewport = { [weak coordinator, weak surface] size in
                guard let coordinator, let surface else { return }
                if let pending = surface.pendingPlace {
                    if pending == place { return }
                    surface.tearDown()
                }
                let transition = DastakEnvironmentTransition(from:coordinator.currentPlace,to:place,
                    reducedMotion:reducedMotion,active:active)
                let updateScene: () -> Void = { [weak coordinator] in
                    coordinator?.update(place,weather:weather,reduceMotion:reducedMotion,active:active,
                        viewport:size,portrait:portrait)
                }
                if coordinator.currentPlace != place && transition.dissolves,
                   let id = surface.prepareDissolve(duration:transition.duration) {
                    surface.startDissolveWhenCovered(id,place:place,update:updateScene)
                } else { updateScene() }
            }
            surface.updateViewport?(surface.bounds.size)
        }
        context.coordinator.holdEyes(heldEyes)
        let info = ProcessInfo.processInfo
        let policy = DastakEnvironmentRenderPolicy(active:active, reducedMotion:reducedMotion,
            lowPower:info.isLowPowerModeEnabled, thermalLimited:info.thermalState == .critical || info.thermalState == .serious)
        view.isPlaying = policy.animates
        view.scene?.isPaused = !policy.animates
        view.rendersContinuously = policy.animates
        view.preferredFramesPerSecond = policy.framesPerSecond
    }
    static func dismantleUIView(_ view: SCNView, coordinator: DastakEnvironmentScene) {
        (view as? NativeEnvironmentSceneView)?.tearDown()
        (view as? NativeEnvironmentSceneView)?.updateViewport = nil
        coordinator.finishTransition()
        view.isPlaying = false; view.scene = nil
    }
}

/// SceneKit renders off the main actor. Match a completed destination frame to
/// its request, then hand off only the fade start to the main actor.
private final class NativeEnvironmentFrameObserver: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (id: UUID, completion: @Sendable (UUID) -> Void)?
    private var renderingID: UUID?
    func arm(_ id: UUID, completion: @escaping @Sendable (UUID) -> Void) {
        lock.lock(); defer { lock.unlock() }
        pending = (id,completion); renderingID = nil
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        pending = nil; renderingID = nil
    }
    func renderer(_ renderer: any SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        renderingID = pending?.id
    }
    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        let completed = pending?.id == renderingID ? pending : nil
        if completed != nil { pending = nil }
        renderingID = nil
        lock.unlock()
        if let completed { completed.completion(completed.id) }
    }
}

/// Keeps scene/lens updates together, and owns a short-lived snapshot only while
/// dissolving between stores. It never captures the shopping panel or account data.
@MainActor
private final class NativeEnvironmentSceneView: SCNView {
    var updateViewport: ((CGSize) -> Void)?
    private var lastSize: CGSize = .zero
    private var dissolve: UIImageView?
    private var fade: UIViewPropertyAnimator?
    private let frameObserver = NativeEnvironmentFrameObserver()
    private var dissolveID: UUID?
    private var dissolveDuration: Double = 0
    private var sceneUpdateLink: CADisplayLink?
    private var pendingSceneUpdate: (id: UUID, place: DastakEnvironmentPlace, action: () -> Void)?
    var pendingPlace: DastakEnvironmentPlace? { pendingSceneUpdate?.place }
    override func layoutSubviews() {
        super.layoutSubviews()
        dissolve?.frame = bounds
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        updateViewport?(bounds.size)
    }
    func prepareDissolve(duration: Double) -> UUID? {
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return nil }
        // Capture once per service switch, never per frame. Blend an interrupted fade
        // into the next snapshot so rapid taps cannot resurrect an older scene.
        let rendered = snapshot()
        let oldImage = dissolve?.image
        let oldAlpha = dissolve?.layer.presentation()?.opacity ?? Float(dissolve?.alpha ?? 0)
        let image = oldImage == nil ? rendered : UIGraphicsImageRenderer(size:bounds.size).image { _ in
            rendered.draw(in:bounds)
            oldImage?.draw(in:bounds,blendMode:.normal,alpha:CGFloat(oldAlpha))
        }
        tearDown()
        let overlay = UIImageView(image:image)
        overlay.frame = bounds; overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        addSubview(overlay); dissolve = overlay
        let id = UUID(); dissolveID = id; dissolveDuration = duration
        return id
    }
    func startDissolveWhenCovered(_ id: UUID, place: DastakEnvironmentPlace, update: @escaping () -> Void) {
        guard dissolveID == id else { return }
        pendingSceneUpdate = (id,place,update)
        let link = CADisplayLink(target:self,selector:#selector(commitCoveredScene))
        link.add(to:.main,forMode:.common); sceneUpdateLink = link
    }
    @objc private func commitCoveredScene() {
        guard let pending = pendingSceneUpdate, dissolveID == pending.id,
              let overlay = dissolve, (overlay.layer.presentation()?.opacity ?? 0) >= 0.99 else { return }
        // Wait for the cover to reach the compositor before changing SceneKit.
        // Otherwise its render thread can expose one destination frame first.
        sceneUpdateLink?.invalidate(); sceneUpdateLink = nil
        pendingSceneUpdate = nil
        pending.action()
        // Keep the old image fully opaque during destination shader preparation.
        // Starting at updateUIView would spend the fade while the new view stalls.
        delegate = frameObserver
        frameObserver.arm(pending.id) { [weak self] renderedID in
            Task { @MainActor [weak self] in self?.fadeRenderedDestination(renderedID) }
        }
        setNeedsDisplay()
    }
    private func fadeRenderedDestination(_ id: UUID) {
        guard dissolveID == id, let overlay = dissolve else { return }
        let animation = UIViewPropertyAnimator(duration:dissolveDuration,curve:.easeInOut) { overlay.alpha = 0 }
        animation.addCompletion { [weak self, weak overlay] _ in
            overlay?.removeFromSuperview()
            if self?.dissolve === overlay {
                self?.dissolve = nil; self?.fade = nil; self?.dissolveID = nil
            }
        }
        fade = animation; animation.startAnimation()
    }
    func tearDown() {
        sceneUpdateLink?.invalidate(); sceneUpdateLink = nil; pendingSceneUpdate = nil
        frameObserver.cancel(); dissolveID = nil
        fade?.stopAnimation(true); fade = nil
        dissolve?.removeFromSuperview(); dissolve = nil
    }
}

@MainActor
final class DastakEnvironmentScene: NSObject {
    // Only decorative geometry/camera retained across outside/auth → inside view replacement.
    static let shared = DastakEnvironmentScene()
    let scene = SCNScene()
    let camera = SCNNode()
    let grocery = SCNNode(), cafe = SCNNode(), outside = SCNNode()
    private var previous: DastakEnvironmentPlace?
    private var previousMotion: Bool?
    var currentPlace: DastakEnvironmentPlace? { previous }
    private var previousViewport: CGSize = .zero
    private var appliedFrame: EnvironmentFrame?
    private var transitionFrames: (from: EnvironmentFrame, to: EnvironmentFrame)?
    private var displayLink: CADisplayLink?
    private var transitionStart: CFTimeInterval = 0
    private var transitionDuration: Double = 0
    private var transitionElapsed: Double = 0
    private let daylight = SCNNode(), fill = SCNNode()
    private let foodBillingFill = SCNNode()
    private var cafeStaffKey: SCNLight?
    private var trees: [SCNNode] = []
    private var staff: [SCNNode] = []
    private var entryLights: [SCNLight] = []
    private var outsidePavement: SCNMaterial?
    private var materials: [String: SCNMaterial] = [:]
    private let precipitation = SCNNode()
    private lazy var groceryEnvironmentLight = DastakGrocerySceneTextures.lighting()
    private var lastWeather: DastakEnvironmentWeather?
    private var previousWeatherMotion: Bool?
    private lazy var precipitationSprite: UIImage = {
        UIGraphicsImageRenderer(size:CGSize(width:32,height:32)).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.7).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.6,1]) {
                context.cgContext.drawRadialGradient(gradient,startCenter:CGPoint(x:16,y:16),startRadius:0,
                    endCenter:CGPoint(x:16,y:16),endRadius:15,options:[])
            }
        }
    }()
    private var previousHeldEyes: Bool?

    override init() {
        super.init()
        scene.rootNode.addChildNode(grocery); scene.rootNode.addChildNode(cafe); scene.rootNode.addChildNode(outside)
        camera.camera = SCNCamera(); camera.camera?.zNear = 0.06; camera.camera?.zFar = 70
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = true
        camera.camera?.minimumExposure = -3; camera.camera?.maximumExposure = 0
        camera.camera?.exposureOffset = -0.8; camera.camera?.bloomIntensity = 0.04
        camera.camera?.bloomThreshold = 1.6; camera.camera?.fieldOfView = 74
        camera.camera?.projectionDirection = .horizontal
        scene.rootNode.addChildNode(camera)
        daylight.light = SCNLight(); daylight.light?.type = .directional
        daylight.light?.intensity = 450; daylight.light?.castsShadow = true
        daylight.light?.shadowMapSize = CGSize(width: 512,height: 512)
        daylight.light?.shadowSampleCount = 4; daylight.light?.shadowRadius = 3
        daylight.light?.shadowColor = UIColor.black.withAlphaComponent(0.16)
        daylight.eulerAngles = SCNVector3(-0.75,-0.5,0); scene.rootNode.addChildNode(daylight)
        fill.light = SCNLight(); fill.light?.type = .ambient; fill.light?.intensity = 140
        daylight.light?.categoryBitMask = 7; fill.light?.categoryBitMask = 7
        scene.rootNode.addChildNode(fill)
        // Soft front/overhead light for the checkout surfaces, not a harsh face spotlight.
        foodBillingFill.light = SCNLight(); foodBillingFill.light?.type = .omni
        foodBillingFill.light?.intensity = 220; foodBillingFill.light?.categoryBitMask = 4
        foodBillingFill.light?.color = UIColor(red:1,green:0.97,blue:0.91,alpha:1)
        foodBillingFill.light?.attenuationStartDistance = 1
        foodBillingFill.light?.attenuationEndDistance = 5
        foodBillingFill.position = v(0.2,2.5,2.2); foodBillingFill.isHidden = true
        scene.rootNode.addChildNode(foodBillingFill)
        buildGrocery(); buildCafe(); buildOutside()
        // Hidden stores share world coordinates. Keep their local lights from spilling
        // into the other store; staff retains its separate skin/uniform lighting layer.
        grocery.enumerateChildNodes { node,_ in node.light?.categoryBitMask = 1 }
        cafe.enumerateChildNodes { node,_ in
            if node.geometry != nil && node.categoryBitMask != 2 { node.categoryBitMask = 4 }
            if let light = node.light, light.categoryBitMask != 2 { light.categoryBitMask = 6 }
        }
        outside.enumerateChildNodes { node,_ in node.light?.categoryBitMask = 1 }
        scene.rootNode.addChildNode(precipitation)
        scene.fogStartDistance = 26; scene.fogEndDistance = 65
    }

    private struct EnvironmentFrame {
        var position: SIMD3<Float>
        var orientation: simd_quatf
        var projection: simd_float4x4
        var exposure, whitePoint, gray, environment, daylight, ambient, staffKey, counterFill: CGFloat
        var backdrop, fog: SIMD4<Float>
        var entry: CGFloat

        func blended(to target: Self, progress: Double) -> Self {
            let t = CGFloat(progress), f = Float(progress)
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a+(b-a)*t }
            return Self(position:position+(target.position-position)*f,
                orientation:simd_slerp(orientation,target.orientation,f),
                projection:projection+(target.projection-projection)*f,
                exposure:mix(exposure,target.exposure),whitePoint:mix(whitePoint,target.whitePoint),
                gray:mix(gray,target.gray),environment:mix(environment,target.environment),
                daylight:mix(daylight,target.daylight),ambient:mix(ambient,target.ambient),
                staffKey:mix(staffKey,target.staffKey),counterFill:mix(counterFill,target.counterFill),
                backdrop:backdrop+(target.backdrop-backdrop)*f,fog:fog+(target.fog-fog)*f,
                entry:mix(entry,target.entry))
        }
    }

    func finishTransition() {
        displayLink?.invalidate(); displayLink = nil
        if let target = transitionFrames?.to { apply(target) }
        transitionFrames = nil
        grocery.isHidden = previous?.isCafe == true; cafe.isHidden = previous?.isCafe != true
        outside.isHidden = previous != .outside
    }

    @objc private func advanceTransition(_ link: CADisplayLink) {
        // Shader preparation or a busy main thread must not consume the whole glide
        // before the first visible frame. Bound each step and resume from that frame.
        transitionElapsed += DastakEnvironmentTransition.frameStep(link.timestamp-transitionStart)
        transitionStart = link.timestamp
        let fraction = transitionElapsed/transitionDuration
        guard let frames = transitionFrames else { finishTransition(); return }
        apply(frames.from.blended(to:frames.to,progress:DastakEnvironmentTransition.progress(fraction)))
        if fraction >= 1 { finishTransition() }
    }

    private func apply(_ frame: EnvironmentFrame) {
        // Explicit interpolation also covers lens/HDR properties that SceneKit does not
        // implicitly animate. Every value uses the same clock and easing curve.
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        camera.simdPosition = frame.position; camera.simdOrientation = frame.orientation
        camera.camera?.projectionTransform = SCNMatrix4(frame.projection)
        camera.camera?.exposureOffset = frame.exposure
        camera.camera?.whitePoint = frame.whitePoint; camera.camera?.averageGray = frame.gray
        scene.lightingEnvironment.intensity = frame.environment
        daylight.light?.intensity = frame.daylight; fill.light?.intensity = frame.ambient
        cafeStaffKey?.intensity = frame.staffKey; foodBillingFill.light?.intensity = frame.counterFill
        // The storefront moves out of the camera naturally; fading a whole node tree
        // changes every mesh's transparency pipeline and can stall the first glide.
        outside.opacity = 1
        func color(_ v: SIMD4<Float>) -> UIColor {
            UIColor(red:CGFloat(v.x),green:CGFloat(v.y),blue:CGFloat(v.z),alpha:CGFloat(v.w))
        }
        scene.background.contents = color(frame.backdrop); scene.fogColor = color(frame.fog)
        for light in entryLights { light.intensity = frame.entry }
        SCNTransaction.commit(); appliedFrame = frame
    }

    func update(_ place: DastakEnvironmentPlace, weather: DastakEnvironmentWeather, reduceMotion: Bool,
                active: Bool, viewport: CGSize, portrait: Bool) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let placeChanged = previous != place
        let weatherChanged = lastWeather != weather
        let viewportChanged = previousViewport != viewport
        let motionChanged = previousMotion != reduceMotion
        if !active { finishTransition() }
        if placeChanged || weatherChanged || viewportChanged || motionChanged {
            let policy = DastakEnvironmentTransition(from:previous,to:place,reducedMotion:reduceMotion,active:active)
            // A different store is swapped under the surface's snapshot dissolve. Within
            // a store, retain geometry and glide from the currently displayed camera.
            grocery.isHidden = place.isCafe; cafe.isHidden = !place.isCafe
            grocery.opacity = 1; cafe.opacity = 1
            outside.isHidden = previous != .outside && place != .outside
            foodBillingFill.isHidden = false
            let position: SCNVector3, gaze: SCNVector3
            switch place {
            case .outside:
                let p = DastakOutsideSceneReference.position(portrait:portrait)
                let t = DastakOutsideSceneReference.target(portrait:portrait)
                position = v(p[0],p[1],p[2]); gaze = v(t[0],t[1],t[2])
            case .grocery:
                let p = DastakGrocerySceneReference.entrancePosition, t = DastakGrocerySceneReference.entranceTarget
                position = v(p[0],p[1],p[2]); gaze = v(t[0],t[1],t[2])
            // Face the cashier at eye level; portrait projection keeps them above the tall basket.
            case .groceryBilling: position = v(-1.6,1.55,0.592); gaze = v(1.41,1.55,0.592)
            // Keep the overhead menu in the clear space above the shopping panel.
            case .cafe: position = v(0,2.05,-4.25); gaze = v(0,0.50,4.5)
            case .cafeCounter: position = v(0.9,1.55,0.9); gaze = v(0.9,1.55,4.15)
            }
            let pose = SCNNode(); pose.position = position
            if place == .cafeCounter {
                // look(at:) degenerates for the exact opposite of localFront at level pitch.
                pose.eulerAngles = SCNVector3(0,Float.pi,0)
            } else {
                pose.look(at:gaze,up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            }
            let billing = place == .groceryBilling || place == .cafeCounter
            let portraitInterior = portrait && place != .outside
            let lens = SCNCamera(); lens.zNear = 0.06; lens.zFar = 70
            lens.projectionDirection = portraitInterior || place == .outside ? .vertical : .horizontal
            lens.fieldOfView = portraitInterior
                ? (place == .grocery ? DastakGrocerySceneReference.portraitFieldOfView : billing ? 56 : 64)
                : (place == .outside ? DastakOutsideSceneReference.fieldOfView(portrait:portrait) : billing ? 56 : 74)
            var projection = lens.projectionTransform(withViewportSize:viewport)
            projection.m32 += portraitInterior ? (place == .grocery
                ? Float(DastakGrocerySceneReference.portraitProjectionOffset) : billing ? -0.72 : 0) : 0
            let day = weather.daylight
            let isGrocery = place == .grocery || place == .groceryBilling
            let isFoodBilling = place == .cafeCounter
            let target = EnvironmentFrame(position:pose.simdPosition,orientation:pose.simdOrientation,
                projection:simd_float4x4(projection),
                exposure:isGrocery ? -2 : isFoodBilling ? -2.1 : -0.8,
                whitePoint:isFoodBilling ? 4 : 1,gray:isFoodBilling ? 0.12 : 0.18,
                environment:isGrocery ? 0.58 : isFoodBilling ? 0.12 : place == .outside ? 0.08+0.32*day : 0.0001,
                daylight:isGrocery ? 450 : isFoodBilling ? 90 : 45+400*day*(1-weather.cloud*0.45),
                ambient:isGrocery ? 140 : isFoodBilling ? 100 : 65+100*day,
                staffKey:isFoodBilling ? 8 : 35,counterFill:isFoodBilling ? 220 : 0,
                backdrop:SIMD4(Float(0.035+0.55*day),Float(0.055+0.67*day),Float(0.11+0.72*day),place == .outside ? 0 : 1),
                fog:SIMD4(Float(0.12+0.6*day),Float(0.14+0.62*day),Float(0.2+0.6*day),1),entry:1+19*(1-day))
            // Keep the IBL resource resident at negligible intensity when unused, rather than
            // switching texture sources (and flashing) halfway through a camera move.
            scene.lightingEnvironment.contents = groceryEnvironmentLight
            camera.camera?.wantsExposureAdaptation = false
            displayLink?.invalidate(); displayLink = nil
            transitionDuration = policy.dissolves || viewportChanged || policy.duration == 0 ? 0
                : placeChanged ? policy.duration : 1.2
            previous = place; previousMotion = reduceMotion; previousViewport = viewport
            if let start = appliedFrame, transitionDuration > 0 {
                transitionFrames = (start,target); transitionStart = CACurrentMediaTime(); transitionElapsed = 0
                let link = CADisplayLink(target:self,selector:#selector(advanceTransition(_:)))
                let info = ProcessInfo.processInfo
                link.preferredFramesPerSecond = DastakEnvironmentRenderPolicy(active:active,reducedMotion:reduceMotion,
                    lowPower:info.isLowPowerModeEnabled,thermalLimited:info.thermalState == .critical || info.thermalState == .serious).framesPerSecond
                link.add(to:.main,forMode:.common); displayLink = link
            } else {
                transitionFrames = nil; apply(target); finishTransition()
            }
        }
        guard lastWeather != weather || previousWeatherMotion != reduceMotion else { return }
        let previousWeather = lastWeather
        lastWeather = weather; previousWeatherMotion = reduceMotion
        outsidePavement?.roughness.contents = weather.precipitation > 0 && !weather.snow ? 0.43 : 0.91
        if previousWeather?.wind != weather.wind || motionChanged {
            for (index, tree) in trees.enumerated() {
                let current = tree.presentation.eulerAngles
                tree.removeAllActions()
                tree.eulerAngles = reduceMotion ? SCNVector3Zero : current
                if !reduceMotion {
                    let sway = min(0.06, 0.008+weather.wind/900)
                    let a = SCNAction.rotateTo(x:0,y:0,z:CGFloat(sway),duration:2.1+Double(index%3)*0.4,usesShortestUnitArc:true)
                    let b = SCNAction.rotateTo(x:0,y:0,z:CGFloat(-sway),duration:2.1+Double(index%3)*0.4,usesShortestUnitArc:true)
                    a.timingMode = .easeInEaseOut; b.timingMode = .easeInEaseOut
                    tree.runAction(.repeatForever(.sequence([a,b])))
                }
            }
        }
        if reduceMotion {
            precipitation.removeAllParticleSystems()
            return
        }
        // Let existing drops/flakes fall out naturally instead of erasing the whole
        // storm whenever the live weather clock updates. At most two emitters coexist.
        for system in precipitation.particleSystems ?? [] where system.birthRate == 0 {
            precipitation.removeParticleSystem(system)
        }
        if weather.precipitation <= 0 {
            for system in precipitation.particleSystems ?? [] { system.birthRate = 0 }
            return
        }
        if previousWeather?.snow == weather.snow, let system = precipitation.particleSystems?.first {
            system.birthRate = CGFloat(min(700,100+weather.precipitation*130))
            system.acceleration = v(weather.wind/60,0,0)
            return
        }
        for system in precipitation.particleSystems ?? [] { system.birthRate = 0 }
        if weather.precipitation > 0 && !reduceMotion {
            let p = SCNParticleSystem(); p.birthRate = CGFloat(min(700,100+weather.precipitation*130))
            p.particleLifeSpan = weather.snow ? 9 : 1.7
            p.particleSize = weather.snow ? 0.025 : 0.008
            p.particleSizeVariation = weather.snow ? 0.012 : 0.002
            p.particleImage = precipitationSprite
            p.particleColor = weather.snow ? .white : UIColor(white:0.85,alpha:0.6)
            p.birthDirection = .constant; p.birthLocation = .volume; p.blendMode = .alpha
            p.stretchFactor = weather.snow ? 0 : 0.04
            p.emitterShape = SCNBox(width:24,height:0.1,length:18,chamferRadius:0)
            p.emittingDirection = v(0,-1,0); p.particleVelocity = weather.snow ? 0.8 : 8
            p.acceleration = v(weather.wind/60,0,0); p.spreadingAngle = weather.snow ? 12 : 3
            precipitation.position = v(0,6,-10); precipitation.addParticleSystem(p)
        }
    }

    func holdEyes(_ closed: Bool?) {
        guard previousHeldEyes != closed else { return }; previousHeldEyes = closed
        for character in staff {
            character.removeAction(forKey:"real eyelid blink")
            character.enumerateChildNodes { mesh,_ in mesh.morpher?.setWeight(closed == true ? 1 : 0,forTargetAt:0) }
            if closed != true { character.runAction(blinkAction(),forKey:"real eyelid blink") }
        }
    }
    private func blinkAction() -> SCNAction {
        let blink=SCNAction.customAction(duration:0.38) { character,time in
            let t=Double(time)/0.38
            let weight: CGFloat = CGFloat(t < 0.28 ? t/0.28 : t < 0.5 ? 1 : max(0,(1-t)/0.5))
            character.enumerateChildNodes { mesh,_ in mesh.morpher?.setWeight(weight,forTargetAt:0) }
        }
        return .repeatForever(.sequence([.wait(duration:4.6),blink]))
    }

    // The approved web layout looks along +Z; SceneKit's screen-right is -X there.
    // Reflect positions/camera, not mesh/UV data or text, to retain the approved sides.
    private func v(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(Float(-x),Float(y),Float(z)) }
    private func material(_ hex: UInt32, roughness: Double = 0.6, metal: Double = 0, texture: String? = nil) -> SCNMaterial {
        let key = "\(hex)-\(roughness)-\(metal)-\(texture ?? "")"
        if let cached = materials[key] { return cached }
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
        m.roughness.contents = roughness; m.metalness.contents = metal
        if let texture, let url = Bundle.module.url(forResource:texture,withExtension:nil) {
            m.diffuse.contents = UIImage(contentsOfFile:url.path)
            let normal = texture.replacingOccurrences(of:"-color.jpg",with:"-normal.jpg")
            if normal != texture, let url = Bundle.module.url(forResource:normal,withExtension:nil) { m.normal.contents = UIImage(contentsOfFile:url.path) }
            m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        }
        materials[key] = m; return m
    }
    @discardableResult private func box(_ parent: SCNNode, _ name: String, _ x: Double, _ y: Double, _ z: Double,
        _ w: Double, _ h: Double, _ d: Double, _ m: SCNMaterial, bevel: Double = 0.015) -> SCNNode {
        let g = SCNBox(width:CGFloat(w),height:CGFloat(h),length:CGFloat(d),chamferRadius:CGFloat(min(bevel,min(w,min(h,d))/4)))
        g.materials = [m]; let n = SCNNode(geometry:g); n.name = name; n.position = v(x,y,z); parent.addChildNode(n); return n
    }
    @discardableResult private func cylinder(_ parent: SCNNode, _ name: String, _ x: Double, _ y: Double, _ z: Double,
        _ radius: Double, _ height: Double, _ m: SCNMaterial) -> SCNNode {
        let g = SCNCylinder(radius:CGFloat(radius),height:CGFloat(height)); g.radialSegmentCount = 12; g.materials = [m]
        let n = SCNNode(geometry:g); n.name = name; n.position = v(x,y,z); parent.addChildNode(n); return n
    }
    private func sign(_ parent: SCNNode, _ text: String, _ x: Double, _ y: Double, _ z: Double, width: Double, height: Double) {
        box(parent,"sign backing",x,y,z,width,height,0.035,material(0x242b2d))
        let g = SCNText(string:text,extrusionDepth:0.001); g.font = UIFont.systemFont(ofSize:12,weight:.semibold)
        let ink=SCNMaterial(); ink.lightingModel = .constant
        ink.diffuse.contents=UIColor(red:0.97,green:0.96,blue:0.91,alpha:1)
        g.flatness = 0.4; g.firstMaterial = ink
        let n = SCNNode(geometry:g); let (lo,hi) = g.boundingBox
        let scale = min(Float(width*0.87)/max(1,hi.x-lo.x),Float(height*0.65)/max(1,hi.y-lo.y))
        n.scale = SCNVector3(scale,scale,scale)
        n.pivot = SCNMatrix4MakeTranslation((lo.x+hi.x)/2,(lo.y+hi.y)/2,0)
        n.eulerAngles.y = .pi; n.position = v(x,y,z-0.024); parent.addChildNode(n)
    }
    private func room(_ root: SCNNode, cafe: Bool) {
        let wall = material(cafe ? 0xd8d3c7 : 0xe6e9e8)
        if cafe { buildCafeArchitecture(root); return }
        let fixtures = SCNNode(), charcoal = material(0x15191e,roughness:0.5,metal:0.15)
        let steel = material(0xaab4b9,roughness:0.32,metal:0.7)
        let floor = SCNMaterial(); floor.lightingModel = .physicallyBased; floor.roughness.contents = 0.3
        floor.diffuse.contents = DastakGrocerySceneTextures.floor()
        floor.diffuse.wrapS = .repeat; floor.diffuse.wrapT = .repeat
        // The room previously began at z=-7, in front of the z=-3.2 shopfront.
        // From outside this exposed several metres of ceiling/walls as a dark canopy.
        let roomFront = -3.2, roomBack = 19.0
        let roomDepth = roomBack-roomFront, roomCenter = (roomBack+roomFront)/2
        floor.diffuse.contentsTransform = SCNMatrix4MakeScale(14/1.2,Float(roomDepth/1.2),1)
        let ground = SCNPlane(width:14,height:roomDepth); ground.materials = [floor]
        let groundNode = SCNNode(geometry:ground); groundNode.eulerAngles.x = -.pi/2
        groundNode.position = v(0,-0.003,roomCenter); fixtures.addChildNode(groundNode)
        box(fixtures,"back wall",0,1.8,18,14,3.6,0.25,wall)
        box(fixtures,"left wall",-3.9,1.8,roomCenter,0.2,3.6,roomDepth,charcoal)
        box(fixtures,"right wall",3,1.8,roomCenter,0.2,3.6,roomDepth,wall)
        box(fixtures,"dark exposed ceiling",-0.45,3.8,roomCenter,7.1,0.18,roomDepth,material(0x171e23,roughness:0.95))
        let wallBase = material(0x636e75,roughness:0.7)
        box(fixtures,"wall plinth",2.875,0.19,roomCenter,0.055,0.38,roomDepth,wallBase)
        box(fixtures,"impact rail",2.84,0.91,roomCenter,0.06,0.075,roomDepth,steel)
        for z in stride(from:-2.0,to:18,by:1.5) { box(fixtures,"wall reveal",2.889,1.87,z,0.012,2.96,0.012,wallBase,bevel:0) }
        box(fixtures,"perimeter light channel",2.83,3.19,roomCenter,0.16,0.12,roomDepth,charcoal)
        box(fixtures,"perimeter diffuser",2.74,3.17,roomCenter,0.025,0.038,roomDepth,glow(0xf5fff5))
        for z in stride(from:-2.0,to:18,by:3.2) {
            box(fixtures,"exposed beam",-0.45,3.57,z,7.1,0.23,0.14,charcoal)
            let pipe = cylinder(fixtures,"service pipe",-0.45,3.64,z+0.65,0.04,7.1,steel); pipe.eulerAngles.z = .pi/2
        }
        for x in [-3.65,2.75] { box(fixtures,"ventilation duct",x,3.61,roomCenter,0.38,0.19,roomDepth,charcoal) }
        for x in [-2.2,1.3] {
            box(fixtures,"lighting track",x,3.43,roomCenter,0.065,0.08,roomDepth,charcoal)
            for z in stride(from:-1.6,to:18,by:3.2) {
                box(fixtures,"light housing",x,3.35,z,0.22,0.1,3.1,steel)
                box(fixtures,"light diffuser",x,3.29,z,0.17,0.025,3,glow(0xfafcf8))
            }
        }
        grocerySign(fixtures,"DASTAK",subtitle:"GOOD THINGS, CLOSE TO HOME",x:0,y:2.85,z:17.8,width:4.2,height:1)
        root.addChildNode(fixtures.flattenedClone())
        for z in [0.0,6.0,12.0] {
            let n=SCNNode(); n.light=SCNLight(); n.light?.type = .omni; n.light?.intensity = 120
            n.light?.attenuationStartDistance=1; n.light?.attenuationEndDistance=9
            n.position=v(0,3.1,z); root.addChildNode(n)
        }
    }
    private func shelf(_ parent: SCNNode, x: Double, z: Double, width: Double, length: Double, seed: Int) {
        let enamel=material(0xaab4b9,roughness:0.32,metal:0.7), dark=material(0x15191e)
        box(parent,"shelf plinth",x,0.12,z,width,0.24,length,dark)
        box(parent,"gondola back",x,1.12,z,0.06,2.1,length,dark)
        for (level,y) in DastakGrocerySceneReference.shelfLevels.enumerated() {
            box(parent,"enamel shelf",x,y,z,width,0.045,length,enamel)
            for side in [-1.0,1.0] {
                box(parent,"shelf ticket rail",x+side*width/2,y+0.02,z,0.018,0.058,length,dark)
                for i in 0..<Int(length/0.24)-1 {
                    let family = (i/5+level*3+seed)%12
                    groceryPack(parent,x:x+side*(width/2-0.14),y:y+0.025,z:z-length/2+0.2+Double(i)*0.24,
                                family:family,rotation:side * .pi/2,size:0.24+Double(family%3)*0.014)
                    if i%5 == 0 { groceryTicket(parent,x:x+side*(width/2+0.012),y:y+0.026,z:z-length/2+0.4+Double(i)*0.24,side:side) }
                }
            }
        }
        for end in [-1.0,1.0] { box(parent,"shelf upright",x,1.15,z+end*length/2,0.09,2.3,0.09,enamel) }
    }
    private func buildGrocery() {
        room(grocery,cafe:false)
        let fixtures = SCNNode(), steel=material(0xaab4b9,roughness:0.32,metal:0.7), dark=material(0x15191e)
        for (index,x) in DastakGrocerySceneReference.shelfCenters.enumerated() {
            shelf(fixtures,x:x,z:9,width:1,length:10,seed:Int((x+10).rounded()))
            for (level,y) in DastakGrocerySceneReference.shelfLevels.enumerated() {
                cylinder(fixtures,"rounded stocked endcap",x,y,3.75,0.55,0.055,dark)
                for n in 0..<7 {
                    let angle = -Double.pi / 2 + Double(n) * .pi / 6
                    groceryPack(fixtures,x:x+sin(angle)*0.41,y:y+0.03,z:3.75-cos(angle)*0.41,
                                family:(level+Int((x+4).rounded()))%12,rotation:-angle,size:0.28)
                }
                groceryTicket(fixtures,x:x,y:y,z:3.18,side:0)
            }
            grocerySign(fixtures,index == 0 ? "01 / Grocery" : "02 / Snacks & home",subtitle:"DASTAK / EVERYDAY ESSENTIALS",
                        x:x,y:2.9,z:4.8,width:1.85,height:0.56)
            for offset in [-0.75,0.75] { cylinder(fixtures,"sign suspension",x+offset,3.33,4.8,0.0065,0.6,dark) }
            if index == 1 { grocerySign(fixtures,"PANTRY PICKS",subtitle:"EVERYDAY ESSENTIALS",x:x,y:2.25,z:3.69,width:1.08,height:0.22,background:0x244438) }
        }
        // Single-sided wall stock, beyond checkout rather than filling its staff bay.
        box(fixtures,"wall stock back",2.87,1.13,8.6,0.04,2.2,11.2,dark)
        box(fixtures,"wall stock plinth",2.6,0.14,8.6,0.54,0.28,11.2,dark)
        for (level,y) in DastakGrocerySceneReference.shelfLevels.enumerated() {
            box(fixtures,"wall stock shelf",2.6,y,8.6,0.54,0.045,11.2,steel)
            for n in 0..<44 {
                let z = 3.18+Double(n)*0.25
                groceryPack(fixtures,x:2.48,y:y+0.025,z:z,family:(n/5+level*3)%12,rotation: -.pi/2,size:0.25)
                if n%5 == 0 { groceryTicket(fixtures,x:2.318,y:y+0.026,z:z,side:-1) }
            }
        }
        for z in stride(from:2.5,to:17,by:1.25) {
            box(fixtures,"fridge cabinet",-3.25,1.23,z,1.05,2.46,1.22,dark)
            box(fixtures,"fridge interior",-2.705,1.27,z,0.012,2.15,1.12,material(0xe6e9e8))
            for level in 0..<5 {
                let y = 0.36+Double(level)*0.4
                box(fixtures,"chilled shelf",-2.7,y,z,0.45,0.025,1.13,steel)
                for k in 0..<4 { groceryPack(fixtures,x:-2.58,y:y+0.02,z:z-0.4+Double(k)*0.24,family:(level+k)%12,rotation: .pi/2,size:0.29) }
            }
            // Glass stays out of the flattened opaque fixtures. Otherwise the
            // merged geometry can write door depth before rendering chilled stock.
            let glass = groceryDoorMaterial()
            let door = SCNNode(geometry: SCNPlane(width:1.15,height:2.2))
            door.name = "transparent fridge door"
            door.geometry?.materials = [glass]
            door.position = v(-2.37,1.27,z); door.eulerAngles.y = -.pi/2
            door.renderingOrder = 20; door.castsShadow = false
            grocery.addChildNode(door)
            for end in [-1.0,1.0] {
                box(fixtures,"door frame",-2.35,1.25,z+end*0.59,0.05,2.35,0.035,steel)
                box(fixtures,"fridge LED",-2.45,1.3,z+end*0.56,0.024,2.12,0.024,glow(0xd7f4ff))
            }
            for y in [0.075,2.425] {
                box(fixtures,"fridge horizontal frame",-2.35,y,z,0.05,0.045,1.22,steel)
            }
            box(fixtures,"fridge handle",-2.28,1.15,z-0.43,0.06,0.63,0.028,steel)
        }
        grocery.addChildNode(fixtures.flattenedClone())
        let counter=SCNNode(); counter.position=v(1.03,0,0.592); counter.eulerAngles.y = -.pi/2
        grocery.addChildNode(counter); buildCounter(counter,cafe:false)
    }

    private func groceryDoorMaterial() -> SCNMaterial {
        if let cached = materials["fridge-door-glass"] { return cached }
        let glass = SCNMaterial(); glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(red:0.66,green:0.82,blue:0.78,alpha:0.08)
        glass.roughness.contents = 0.12; glass.metalness.contents = 0.15
        glass.blendMode = .alpha; glass.transparencyMode = .singleLayer
        glass.isDoubleSided = true; glass.writesToDepthBuffer = false
        glass.readsFromDepthBuffer = true
        materials["fridge-door-glass"] = glass
        return glass
    }

    private func groceryPrintedMaterial(_ key: String, image: () -> UIImage, roughness: Double = 0.65) -> SCNMaterial {
        if let cached = materials[key] { return cached }
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = image(); m.roughness.contents = roughness
        materials[key] = m; return m
    }
    private func groceryPack(_ parent: SCNNode, x: Double, y: Double, z: Double, family: Int, rotation: Double, size: Double) {
        let i = family%12, height = size*(1+Double(i%4)*0.07)
        let printed = groceryPrintedMaterial("pantry-label-\(i)",image:{ DastakGrocerySceneTextures.package(i) },roughness:i%4 == 2 ? 0.38 : 0.65)
        // Keep static stock geometry in the same coordinate space as the fixtures.
        // SceneKit's flattened clone must not depend on transform-only package parents.
        let centerY = y+height/2
        if i%4 == 0 || i%4 == 3 {
            let radius = size*(i%4 == 3 ? 0.2 : 0.25)
            let jar = cylinder(parent,"printed pantry jar",x,centerY,z,radius,height*0.84,printed)
            jar.eulerAngles.y = Float(-rotation)
            cylinder(parent,"jar cap",x,centerY+height*0.45,z,radius*1.03,height*0.12,material(0x839391,roughness:0.32,metal:0.6))
        } else {
            let pack = box(parent,i%4 == 2 ? "printed pantry pouch" : "printed pantry carton",x,centerY,z,size*0.64,height,size*0.34,printed,bevel:0.012)
            pack.eulerAngles.y = Float(-rotation)
            if i%4 == 2 {
                let seal = box(parent,"pouch seal",x,centerY+height*0.48,z,size*0.60,0.012,size*0.07,printed,bevel:0.002)
                seal.eulerAngles.y = Float(-rotation)
            }
        }
    }
    private func groceryTicket(_ parent: SCNNode, x: Double, y: Double, z: Double, side: Double) {
        let m = groceryPrintedMaterial("pantry-shelf-ticket",image:{ DastakGrocerySceneTextures.ticket() })
        let g = SCNPlane(width:0.21,height:0.052); g.materials = [m]; m.isDoubleSided = true
        let n = SCNNode(geometry:g); n.position = v(x,y,z); n.eulerAngles.y = Float(side == 0 ? .pi : side * .pi/2)
        parent.addChildNode(n)
    }
    private func grocerySign(_ parent: SCNNode, _ title: String, subtitle: String, x: Double, y: Double, z: Double,
                             width: Double, height: Double, background: UInt32 = 0x1d242b) {
        let m = groceryPrintedMaterial("grocery-sign-\(title)",image:{ DastakGrocerySceneTextures.sign(title,subtitle:subtitle,background:background) })
        box(parent,"reference sign backing",x,y,z,width,height,0.035,material(background))
        let g = SCNPlane(width:CGFloat(width),height:CGFloat(height)); g.materials = [m]
        let n = SCNNode(geometry:g); n.position = v(x,y,z-0.02); n.eulerAngles.y = .pi; parent.addChildNode(n)
    }
    private func buildCounter(_ parent: SCNNode, cafe: Bool) {
        let top=cafe ? grainMaterial("quartz",base:0xd9d4c9,roughness:0.46) : material(0x202828,roughness:0.48)
        let equipment=material(0x202828,roughness:0.5)
        let steel=material(0x8c999c,roughness:0.28,metal:0.7)
        let w=cafe ? 4.45 : 1.65
        box(parent,"counter cabinet",0,0.47,0,w,0.94,0.83,material(cafe ? 0x987349 : 0xd8ddda,texture:cafe ? "wood_floor-color.jpg" : nil))
        box(parent,"counter front trim",0,0.74,-0.425,w,0.09,0.035,material(0x922329))
        box(parent,"counter top",0,0.985,0,w+0.1,0.075,0.96,top,bevel:0.03)
        if cafe {
            for x in stride(from:-2.1,through:2.1,by:0.085) {
                box(parent,"oak counter fin",x,0.49,-0.44,0.045,0.82,0.035,material(0xffffff,roughness:0.72,texture:"wood_floor-color.jpg"),bevel:0.008)
            }
            box(parent,"warm counter underlight",0,0.93,-0.45,4.3,0.012,0.018,glow(0xffe1a6))
            sign(parent,"ORDER",-1.3,0.62,-0.475,width:0.68,height:0.16)
            sign(parent,"PICK UP",1.4,0.62,-0.475,width:0.68,height:0.16)
        }
        let terminalX=cafe ? 0.9 : 0.0
        let monitorX=terminalX+(cafe ? -0.30 : 0)
        cylinder(parent,"monitor stem",monitorX,1.11,0.07,0.025,0.23,steel)
        box(parent,"billing screen",monitorX,1.32,0.09,0.28,0.20,0.04,equipment)
        box(parent,"keyboard",terminalX,1.04,0.31,0.36,0.025,0.13,equipment)
        for row in 0..<3 { for k in 0..<9 { box(parent,"keyboard key",terminalX-0.15+Double(k)*0.034,1.058,0.26+Double(row)*0.033,0.024,0.006,0.023,steel,bevel:0.002) } }
        let printerX=terminalX+(cafe ? -0.5 : 0.45)
        box(parent,"receipt printer",printerX,1.10,0.02,0.22,0.17,0.2,equipment)
        box(parent,"receipt",printerX,1.191,-0.01,0.13,0.003,0.16,material(0xf3eee1),bevel:0)
        box(parent,"customer payment device",terminalX+0.4,1.07,-0.32,0.15,0.065,0.2,equipment)
        if !cafe { box(parent,"conveyor",-0.55,1.03,0.0,0.48,0.025,0.8,material(0x172020,roughness:0.95)) }
        if !cafe {
            // Match the web's compact furniture footprint without shrinking the adult.
            for part in parent.childNodes {
                part.position.x *= 0.68; part.position.z *= 0.55
                part.scale.x *= 0.68; part.scale.z *= 0.55
            }
        }
        addStaff(parent,x:terminalX,z:cafe ? 0.53 : 0.38,cafe:cafe)
        if !cafe { grocerySign(parent,"01 / CHECKOUT",subtitle:"WELCOME TO DASTAK",x:0,y:2.3,z:0.38,width:1.65,height:0.25) }
    }
    private func addStaff(_ parent: SCNNode, x: Double, z: Double, cafe: Bool) {
        do {
            let (node,_) = try DastakNativeStaff.load(); node.position=v(x,0,z); parent.addChildNode(node)
            let up=SCNAction.moveBy(x:0,y:0.0025,z:0,duration:2.4),down=SCNAction.moveBy(x:0,y:-0.0025,z:0,duration:2.6)
            up.timingMode = .easeInEaseOut; down.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([up,down])),forKey:"calm breathing")
            node.runAction(blinkAction(),forKey:"real eyelid blink")
            staff.append(node)
            if cafe {
                DastakNativeUniform.attach(to:node)
                node.enumerateChildNodes { part,_ in part.categoryBitMask = 2 }
                let key=SCNNode(); key.light=SCNLight(); key.light?.type = .omni
                key.light?.categoryBitMask=2; key.light?.intensity=35
                cafeStaffKey = key.light
                key.light?.color=UIColor(red:1,green:0.94,blue:0.86,alpha:1)
                key.light?.attenuationStartDistance=0.3; key.light?.attenuationEndDistance=3
                key.position=v(x-0.25,2.1,z-0.8); parent.addChildNode(key)
            }
        } catch {
            // Asset failure must not replace staff with a misleading cartoon or block shopping.
            parent.name = "Staff resource unavailable; commerce unaffected"
        }
    }
    private func glow(_ hex:UInt32)->SCNMaterial {
        let m=material(hex); m.emission.contents=m.diffuse.contents; return m
    }
    private func grainMaterial(_ name:String,base:UInt32,roughness:Double)->SCNMaterial {
        if let cached=materials[name] { return cached }
        let texture=UIGraphicsImageRenderer(size:CGSize(width:256,height:256)).image { context in
            let color=UIColor(red:CGFloat((base>>16)&255)/255,green:CGFloat((base>>8)&255)/255,blue:CGFloat(base&255)/255,alpha:1)
            color.setFill(); context.fill(CGRect(x:0,y:0,width:256,height:256))
            var random=DastakNativeSceneGeometry.Random(seed:674)
            for i in 0..<5000 {
                UIColor(white:i%2==0 ? 1 : 0,alpha:0.008+random.next()*0.018).setFill()
                context.fill(CGRect(x:random.next()*256,y:random.next()*256,width:1+random.next(),height:1+random.next()))
            }
        }
        let m=SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents=texture
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat; m.roughness.contents=roughness
        if name == "quartz" { m.diffuse.contentsTransform=SCNMatrix4MakeScale(4,4,1) }
        materials[name]=m; return m
    }
    private func addFixtures(_ fixtures:SCNNode,to root:SCNNode) {
        // SCNText's pivot/scale shifts when flattened with boxes. Keep the few labels separate.
        for label in fixtures.childNodes where label.geometry is SCNText {
            label.removeFromParentNode(); root.addChildNode(label)
        }
        root.addChildNode(fixtures.flattenedClone())
    }
    private func buildCafeArchitecture(_ root:SCNNode) {
        let fixtures=SCNNode(),black=material(0x252825),oak=material(0xffffff,roughness:0.72,texture:"wood_floor-color.jpg")
        let cream=material(0xd9d4c7,roughness:0.9),red=material(0x8f2025,roughness:0.8)
        box(fixtures,"cafe subfloor",0,-0.08,1.3,5.6,0.14,10.4,black)
        let stone=grainMaterial("limestone",base:0xbfb9ab,roughness:0.72)
        for x in stride(from:-2.8,to:2.8,by:0.8) { for z in stride(from:-3.8,to:6.5,by:0.8) {
            box(fixtures,"limestone slab",x+0.4,-0.005,z+0.4,0.794,0.03,0.794,stone,bevel:0.003)
        } }
        for x in [-2.84,2.84] {
            box(fixtures,"cafe side wall",x,1.72,1.3,0.12,3.44,10.4,cream)
            box(fixtures,"oak lower wall",x+(x<0 ? 0.07 : -0.07),0.65,0.4,0.06,1.3,6.5,oak)
            box(fixtures,"wall skirting",x+(x<0 ? 0.1 : -0.1),0.08,0.4,0.06,0.16,6.5,black)
        }
        box(fixtures,"cafe back wall",0,1.72,6.4,5.6,3.44,0.12,black)
        box(fixtures,"cafe ceiling",0,3.46,1.3,5.6,0.1,10.4,black)
        for z in [-2.5,0,2.5,5.0] {
            box(fixtures,"cafe ceiling beam",0,3.3,z,5.55,0.12,0.1,black)
            for x in [-1.7,1.7] { box(fixtures,"cafe warm rail",x,3.22,z,0.075,0.025,1.4,glow(0xffefd7)) }
        }
        for z in [-1.7,0.45,2.6] {
            box(fixtures,"frosted daylight window",-2.755,2.14,z,0.03,1.55,1.75,glow(0xa9bbb4))
            for dz in [-0.9,0.9] { box(fixtures,"window frame",-2.7,2.14,z+dz,0.15,1.65,0.035,black) }
            box(fixtures,"window sill",-2.63,1.33,z,0.28,0.045,1.88,oak)
        }
        box(fixtures,"right red accent",2.76,2.03,1.2,0.06,1.38,4.25,material(0xbe3025))
        let poster=box(fixtures,"framed decorative food poster",2.715,2.03,0.65,0.035,1.0,1.5,material(0xffffff,texture:"restaurant-burger.jpg"))
        poster.geometry?.firstMaterial?.roughness.contents=0.9
        for z in [-0.17,1.47] { box(fixtures,"poster side frame",2.67,2.03,z,0.07,1.10,0.035,black) }
        for y in [1.48,2.58] { box(fixtures,"poster frame",2.67,y,0.65,0.07,0.035,1.68,black) }
        for z in [-0.2,1.9] {
            box(fixtures,"booth base",-2.38,0.25,z,0.65,0.5,1.72,black,bevel:0.06)
            box(fixtures,"booth seat",-2.32,0.51,z,0.7,0.18,1.74,red,bevel:0.07)
            box(fixtures,"booth back",-2.62,0.92,z,0.19,0.75,1.76,red,bevel:0.06)
            for dz in stride(from:-0.75,through:0.75,by:0.25) {
                box(fixtures,"upholstered channel",-2.505,0.94,z+dz,0.03,0.58,0.19,red)
            }
            box(fixtures,"oak dining table",-1.7,0.78,z,1.08,0.055,0.72,oak,bevel:0.035)
            cylinder(fixtures,"table leg",-1.7,0.38,z,0.035,0.73,black)
            box(fixtures,"table foot",-1.7,0.033,z,0.5,0.055,0.46,black)
            box(fixtures,"ochre chair seat",-0.99,0.465,z,0.44,0.06,0.46,material(0xb67d31),bevel:0.03)
            let back=box(fixtures,"chair back",-0.75,0.74,z,0.045,0.4,0.44,oak,bevel:0.02)
            back.eulerAngles.z = -0.08
            for dx in [-0.16,0.16] { for dz in [-0.17,0.17] { cylinder(fixtures,"chair leg",-0.99+dx,0.23,z+dz,0.014,0.44,black) } }
            box(fixtures,"table tray",-1.7,0.824,z,0.4,0.018,0.28,black)
            cafeCup(fixtures,x:-1.78,y:0.94,z:z)
            cylinder(fixtures,"pendant wire",-1.7,2.99,z,0.004,0.84,black)
            let shade=SCNCone(topRadius:0.06,bottomRadius:0.24,height:0.23); shade.radialSegmentCount=24; shade.materials=[black]
            let n=SCNNode(geometry:shade); n.position=v(-1.7,2.49,z); fixtures.addChildNode(n)
            cylinder(fixtures,"pendant diffuser",-1.7,2.37,z,0.215,0.009,glow(0xffe2ac))
        }
        addFixtures(fixtures,to:root)
        for (x,z) in [(-1.7,0.5),(0.0,3.8)] {
            let n=SCNNode(); n.light=SCNLight(); n.light?.type = .omni; n.light?.intensity=75
            n.light?.color=UIColor(red:1,green:0.9,blue:0.77,alpha:1)
            n.light?.attenuationStartDistance=0.5; n.light?.attenuationEndDistance=5
            n.position=v(x,2.6,z); root.addChildNode(n)
        }
    }
    private func cafeCup(_ root:SCNNode,x:Double,y:Double,z:Double) {
        let paper=material(0xeee9de),red=material(0xbe3025)
        cylinder(root,"decorative paper cup",x,y,z,0.065,0.21,red)
        cylinder(root,"cup lid",x,y+0.11,z,0.07,0.012,paper)
        cylinder(root,"paper straw",x,y+0.19,z,0.004,0.15,paper)
    }
    private func buildCafe() {
        room(cafe,cafe:true)
        let counter=SCNNode(); counter.position=v(0,0,3.62); cafe.addChildNode(counter); buildCounter(counter,cafe:true)
        let fixtures=SCNNode(),steel=material(0xa1a6a3,roughness:0.4,metal:0.85),black=material(0x252825),paper=material(0xeee9de)
        box(fixtures,"charcoal kitchen tile backing",0,1.44,6.33,5.5,2.7,0.06,material(0x283330,roughness:0.36))
        for x in stride(from:-2.7,through:2.7,by:0.3) { box(fixtures,"tile vertical grout",x,1.44,6.29,0.004,2.7,0.002,black,bevel:0) }
        for y in stride(from:0.15,through:2.7,by:0.15) { box(fixtures,"tile horizontal grout",0,y,6.29,5.5,0.004,0.002,black,bevel:0) }
        box(fixtures,"prep counter",0.2,0.9,5.88,3.6,0.085,0.7,steel)
        box(fixtures,"dark kitchen pass",0,1.5,6.235,2.5,0.72,0.045,black)
        box(fixtures,"extraction hood",0,2.02,5.96,2.65,0.28,0.62,steel,bevel:0.03)
        for x in stride(from:-1.2,through:1.2,by:0.075) { box(fixtures,"hood louvre",x,1.89,5.67,0.024,0.045,0.2,black) }
        box(fixtures,"pass warm strip",0,1.85,5.88,2.3,0.015,0.025,glow(0xffe1a6))
        for x in [-0.8,0,0.8] { box(fixtures,"food warmer",x,1.02,5.88,0.63,0.16,0.46,steel); box(fixtures,"pass tray",x,1.115,5.84,0.57,0.016,0.4,black) }
        for i in 0..<6 { box(fixtures,"takeaway box stack",2.2,1.03+Double(i)*0.055,5.85,0.42,0.05,0.32,paper) }
        let oak=material(0xffffff,roughness:0.72,texture:"wood_floor-color.jpg")
        box(fixtures,"menu oak canopy",0,2.78,5.46,5.28,0.85,0.22,oak)
        for i in 0..<3 {
            let x=Double(i-1)*1.5
            box(fixtures,"menu frame",x,2.77,5.292,1.43,0.81,0.065,black)
            let m=material(0xffffff,roughness:0.9,texture:["restaurant-burger.jpg","restaurant-fries.jpg","restaurant-chicken.jpg"][i])
            box(fixtures,"decorative menu photograph",x,2.85,5.251,1.34,0.54,0.02,m)
            sign(fixtures,["SIGNATURE BURGERS","GOLDEN FRIES","CRISPY CHICKEN"][i],x,2.48,5.25,width:1.34,height:0.18)
        }
        // Mount on the customer-facing side of the z=5 ceiling beam, not behind it.
        sign(fixtures,"DASTAK / KITCHEN",0,3.28,4.92,width:3.75,height:0.22)
        // A decorative kiosk stays to the right of the walking path, never a commerce control.
        let x=1.6,z=2.05
        box(fixtures,"kiosk base",x,0.04,z,0.6,0.07,0.48,black)
        box(fixtures,"kiosk stem",x,0.65,z,0.17,1.2,0.15,black)
        box(fixtures,"kiosk shell",x,1.51,z,0.56,0.91,0.10,paper,bevel:0.04)
        box(fixtures,"kiosk bezel",x,1.53,z-0.06,0.5,0.81,0.015,black)
        box(fixtures,"kiosk food photograph",x,1.59,z-0.075,0.44,0.3,0.012,material(0xffffff,texture:"restaurant-burger.jpg"))
        sign(fixtures,"ORDER HERE",x,1.87,z-0.08,width:0.43,height:0.08)
        sign(fixtures,"WELCOME",x,1.31,z-0.08,width:0.43,height:0.16)
        box(fixtures,"pickup tray",1.5,1.03,3.62,0.63,0.02,0.46,black)
        for x in [1.4,1.63] { cafeCup(fixtures,x:x,y:1.16,z:3.65) }
        box(fixtures,"paper takeaway bag",1.98,1.20,3.72,0.24,0.35,0.17,material(0xb58b56),bevel:0.015)
        addFixtures(fixtures,to:cafe)
    }
    private func buildOutside() {
        let z = DastakOutsideSceneReference.z
        let facade=grainMaterial("exterior warm stone",base:0xe6e1d5,roughness:0.8)
        let brand=material(0x203e34,roughness:0.47,metal:0.12)
        let charcoal=material(0x15191e), steel=material(0xaab4b9,roughness:0.32,metal:0.7)
        let bronze=material(0xb6a477,roughness:0.36,metal:0.65)
        let wood=material(0xffffff,roughness:0.8,texture:"wood_floor-color.jpg")
        let pavement=material(0xffffff,roughness:0.91,texture:"exterior-pavement-color.jpg")
        outsidePavement=pavement
        pavement.diffuse.contentsTransform=SCNMatrix4MakeScale(10,14/3,1)
        pavement.normal.contentsTransform=pavement.diffuse.contentsTransform
        pavement.normal.wrapS = .repeat; pavement.normal.wrapT = .repeat
        let ground=SCNPlane(width:30,height:14); ground.materials=[pavement]
        let paving=SCNNode(geometry:ground); paving.name="reference limestone forecourt"
        paving.eulerAngles.x = -.pi/2; paving.position=v(-0.5,-0.025,z(-14)); outside.addChildNode(paving)
        for x in [-1.75,0.75] { box(outside,"entry path border",x,-0.009,z(-13.9),0.055,0.006,12.3,brand) }
        box(outside,"entrance drain channel",-0.5,-0.005,z(-8.7),7.5,0.025,0.11,charcoal)
        for x in stride(from:-4.0,to:3,by:0.1) { box(outside,"drain grating",x,0.01,z(-8.7),0.012,0.006,0.1,steel) }
        box(outside,"entry threshold",-0.5,-0.005,z(-7.1),7.4,0.06,0.42,steel)
        box(outside,"storefront fascia",-0.5,3.25,z(-7.16),7.5,1.2,0.35,material(0x202925,roughness:0.86))
        box(outside,"fascia upper shadow reveal",-0.5,3.82,z(-7.36),7.5,0.035,0.025,charcoal)
        box(outside,"fascia lower shadow reveal",-0.5,2.68,z(-7.36),7.5,0.025,0.025,charcoal)
        exteriorSign("DASTAK",subtitle:"GOOD THINGS, CLOSE TO HOME",x:-0.5,y:3.27,z:z(-7.36),width:6.95,height:1.02)
        box(outside,"storefront canopy",-0.5,2.7,z(-7.65),7.65,0.13,1.25,charcoal)
        box(outside,"canopy light strip",-0.5,2.625,z(-8.12),6.95,0.025,0.035,glow(0xffead0))
        for x in [-4.05,3.05] {
            box(outside,"warm stone entrance pier",x,1.31,z(-7.16),0.45,2.62,0.4,facade)
            for i in 0..<6 { box(outside,"entrance oak slat",x-0.18+Double(i)*0.072,1.3,z(-7.39),0.035,2.5,0.06,wood) }
        }
        let glass=SCNMaterial(); glass.lightingModel = .physicallyBased
        glass.diffuse.contents=UIColor(red:0.5,green:0.67,blue:0.63,alpha:0.08)
        glass.roughness.contents=0.08; glass.blendMode = .alpha
        glass.transparencyMode = .aOne; glass.writesToDepthBuffer=false
        for x in [-2.47,1.47] {
            box(outside,"shopfront window",x,1.3,z(-7.18),2.54,2.5,0.025,glass)
            for dx in [-1.28,1.28] { box(outside,"window mullion",x+dx,1.3,z(-7.22),0.045,2.6,0.06,charcoal) }
            box(outside,"window safety strip",x,0.99,z(-7.2),2.5,0.025,0.015,steel)
        }
        for x in [-1.65,0.65] {
            box(outside,"parked sliding door",x,1.27,z(-7.31),0.86,2.45,0.018,glass)
            box(outside,"sliding door edge",x+(x<0 ? 0.44 : -0.44),1.27,z(-7.33),0.026,2.45,0.035,steel)
        }
        box(outside,"welcome mat",-0.5,0.018,z(-7.85),1.9,0.035,1.1,charcoal)
        exteriorSign("WELCOME IN",subtitle:"FRESH PICKS · EVERY DAY",x:-0.5,y:2.43,z:z(-7.25),width:1.72,height:0.24)
        let shrubMaterial=material(0x87a961,roughness:0.79); shrubMaterial.isDoubleSided=true
        for x in [-3.5,2.5] {
            box(outside,"entrance planter",x,0.25,z(-8.2),0.65,0.5,0.65,brand,bevel:0.035)
            let shrub=leafNode("entrance planting",count:480,seed:x<0 ? 21 : 34,material:shrubMaterial)
            shrub.scale=SCNVector3(0.23,0.31,0.23); shrub.position=v(x,0.82,z(-8.2)); outside.addChildNode(shrub)
        }
        for x in [-3.85,2.85] {
            box(outside,"forecourt planter",x,0.29,z(-10.75),0.65,0.58,2.4,brand,bevel:0.035)
            let shrub=leafNode("forecourt border planting",count:1100,seed:x<0 ? 41 : 73,hedge:true,material:shrubMaterial)
            shrub.scale=SCNVector3(0.22,0.14,3)
            shrub.position=v(x,0.58,z(-10.75)); outside.addChildNode(shrub)
            let seatX=x+(x < -0.5 ? 0.64 : -0.64)
            for dx in [-0.17,0,0.17] { box(outside,"oak bench slat",seatX+dx,0.46,z(-10.55),0.145,0.06,1.6,wood) }
            for seatZ in [-11.13,-9.97] { box(outside,"bench leg",seatX,0.23,z(seatZ),0.48,0.46,0.07,charcoal) }
            cylinder(outside,"path bollard",x,0.37,z(-12.35),0.13,0.74,brand)
            cylinder(outside,"bollard light ring",x,0.64,z(-12.35),0.135,0.04,glow(0xffead0))
            let lamp=SCNNode(); lamp.light=SCNLight(); lamp.light?.type = .omni
            lamp.light?.color=UIColor(red:1,green:0.8,blue:0.48,alpha:1); lamp.light?.attenuationEndDistance=4
            lamp.position=v(x,0.7,z(-12.35)); outside.addChildNode(lamp)
            if let light=lamp.light { entryLights.append(light) }
        }
        let foliage=material(0x779957,roughness:0.9); foliage.isDoubleSided=true
        let bark=grainMaterial("bark",base:0x625448,roughness:1)
        for side in [-1.0,1.0] {
            // Dense evergreen banks close the side horizon without adding buildings.
            let edge=side<0 ? -4.28 : 3.28
            box(outside,"evergreen screen core",edge+side*12,1.65,z(-5.7),24,3.5,2.4,material(0x354927,roughness:1))
            for i in 0..<5 {
                let hedge=leafNode("batched evergreen bank",count:2400,seed:UInt32(90+i+(side<0 ? 0 : 20)),hedge:true,material:foliage)
                hedge.scale=SCNVector3(2.72,1.38,1)
                hedge.position=v(edge+side*(3.05+Double(i)*6),0,z(-7.5))
                outside.addChildNode(hedge); trees.append(hedge)
            }
            for i in 0..<3 {
                let tree=SCNNode(); tree.position=v(side*(6.0+Double(i)*2.5),0,z(-4+Double(i)*8))
                let trunk=SCNCone(topRadius:0.045,bottomRadius:0.16,height:3.2)
                trunk.radialSegmentCount=10; trunk.materials=[bark]
                let n=SCNNode(geometry:trunk); n.position=v(0,1.6,0); tree.addChildNode(n)
                for j in 0..<5 {
                    let a=Double(j)*2.39996,start=v(0,1.7+Double(j)*0.12,0),end=v(cos(a)*0.7,2.9+Double(j)*0.12,sin(a)*0.7)
                    let dx=end.x-start.x,dy=end.y-start.y,dz=end.z-start.z
                    let g=SCNCone(topRadius:0.018,bottomRadius:0.04,height:CGFloat(sqrt(dx*dx+dy*dy+dz*dz)))
                    g.radialSegmentCount=8; g.materials=[bark]
                    let branch=SCNNode(geometry:g); branch.position=SCNVector3((start.x+end.x)/2,(start.y+end.y)/2,(start.z+end.z)/2)
                    branch.look(at:end,up:SCNVector3(0,0,1),localFront:SCNVector3(0,1,0)); tree.addChildNode(branch)
                }
                let crown=leafNode("batched folded leaf crown",count:1800,seed:UInt32(200+i+(side<0 ? 0 : 20)),material:foliage)
                crown.position=v(0,3.3,0); tree.addChildNode(crown)
                outside.addChildNode(tree); trees.append(crown)
            }
        }
    }
    private func exteriorSign(_ title:String,subtitle:String,x:Double,y:Double,z:Double,width:Double,height:Double) {
        let m=SCNMaterial(); m.lightingModel = .physicallyBased; m.roughness.contents=0.47
        let image=DastakGrocerySceneTextures.exteriorSign(title,subtitle:subtitle)
        m.diffuse.contents=image
        m.emission.contents=title == "DASTAK" ? DastakGrocerySceneTextures.exteriorSign(title,subtitle:subtitle,emissionMask:true) : image
        m.emission.intensity=title == "DASTAK" ? 0.85 : 0.4
        if title == "DASTAK" { m.roughness.contents=0.86 }
        let plane=SCNPlane(width:width,height:height); plane.materials=[m]
        let node=SCNNode(geometry:plane); node.position=v(x,y,z-0.024); node.eulerAngles.y = .pi
        outside.addChildNode(node)
    }
    private func leafNode(_ name:String,count:Int,seed:UInt32,hedge:Bool=false,material:SCNMaterial)->SCNNode {
        let mesh=DastakNativeSceneGeometry.leaves(count:count,seed:seed,hedge:hedge)
        func source(_ values:[Float],_ semantic:SCNGeometrySource.Semantic,_ components:Int)->SCNGeometrySource {
            let data=values.withUnsafeBufferPointer { Data(buffer:$0) }
            return SCNGeometrySource(data:data,semantic:semantic,vectorCount:values.count/components,
                usesFloatComponents:true,componentsPerVector:components,bytesPerComponent:4,dataOffset:0,dataStride:components*4)
        }
        let geometry=SCNGeometry(sources:[source(mesh.positions,.vertex,3),source(mesh.normals,.normal,3),source(mesh.colors,.color,4)],
            elements:[SCNGeometryElement(indices:mesh.indices,primitiveType:.triangles)])
        geometry.materials=[material]
        let node=SCNNode(geometry:geometry); node.name=name; return node
    }
}
#endif
