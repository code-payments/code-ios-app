import SwiftUI
import SceneKit
import CoreMotion

/// Hosts the gold-bar SCNView. Device tilt leans the bar slightly (sweeping its
/// reflections); the key light stays fixed at its anchor. Camera never moves.
struct GoldBarSceneView: UIViewRepresentable {

    let key: GoldBarTextureStore.Key
    var lightIntensity: Double
    var environmentIntensity: Double
    var relief: Double
    /// Rest position of the key light.
    var lightAnchor: SIMD2<Double>
    /// Base bar rotation in degrees: x turns left/right, y tilts up/down; device
    /// motion adds a slight lean on top of this.
    var barRotationDegrees: SIMD2<Double>
    /// Called once the scene is attached and renderable — the placeholder above can fade out.
    var onSceneReady: () -> Void

    /// Past the cover transition (~0.5s): every SceneKit/Metal step (view
    /// creation, shader compile, scene attach) lands main-thread hitches, so all
    /// of it is deferred until the placeholder hides it.
    private static let sceneAttachDelay: Duration = .milliseconds(600)

    func makeCoordinator() -> Coordinator { Coordinator(key: key) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let coordinator = context.coordinator
        let onReady = onSceneReady
        Task {
            try? await Task.sleep(for: Self.sceneAttachDelay)
            guard !coordinator.isStopped else { return }

            let bundle = await coordinator.buildSceneIfNeeded()
            guard !coordinator.isStopped else { return }
            let view = SCNView()
            view.backgroundColor = .clear
            view.antialiasingMode = .multisampling2X
            view.allowsCameraControl = false
            await withCheckedContinuation { continuation in
                view.prepare([bundle.scene]) { _ in
                    continuation.resume()
                }
            }
            guard !coordinator.isStopped else { return }

            view.scene = bundle.scene
            view.frame = container.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(view)
            coordinator.scnView = view
            coordinator.start()
            onReady()
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Scalars only — never reassign `.contents` here or the baked roughness/normal maps are lost.
        // Each write is guarded so unrelated SwiftUI updates don't dirty the SceneKit scene.
        let coordinator = context.coordinator
        coordinator.setLightAnchor(lightAnchor)
        coordinator.setBaseRotation(barRotationDegrees)
        guard let bundle = coordinator.bundle else { return }  // re-applied via the onSceneReady re-render
        if coordinator.appliedLightIntensity != lightIntensity {
            coordinator.appliedLightIntensity = lightIntensity
            bundle.keyLightNode.light?.intensity = CGFloat(lightIntensity)
        }
        if coordinator.appliedEnvironmentIntensity != environmentIntensity {
            coordinator.appliedEnvironmentIntensity = environmentIntensity
            bundle.scene.lightingEnvironment.intensity = CGFloat(environmentIntensity)
        }
        if coordinator.appliedRelief != relief {
            coordinator.appliedRelief = relief
            bundle.material.normal.intensity = CGFloat(relief)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private(set) var bundle: GoldBarScene.Bundle?
        var appliedLightIntensity: Double?
        var appliedEnvironmentIntensity: Double?
        var appliedRelief: Double?

        weak var scnView: SCNView?

        // start() can arrive after stop() when the cover is dismissed mid-prepare —
        // motion must not be left running on a torn-down view.
        private(set) var isStopped = false

        private let key: GoldBarTextureStore.Key
        private let motion = CMMotionManager()
        // Start near the neutral held attitude so the first frame is already centered.
        private var smoothedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)
        private var lastAppliedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)
        private var lightAnchor = GoldBarLighting.restAnchor
        private var baseRotation = SIMD2<Double>(0, 0)
        private var motionRotation = SIMD2<Double>(0, 0)

        init(key: GoldBarTextureStore.Key) {
            self.key = key
        }

        /// Awaits the store's full-resolution maps (already baked or in flight
        /// when `showCashBill` preheated) and assembles the scene once.
        func buildSceneIfNeeded() async -> GoldBarScene.Bundle {
            if let bundle { return bundle }
            let textures = await GoldBarTextureStore.shared.textures(for: key)
            let built = GoldBarScene.make(textures: textures)
            bundle = built
            positionLight()
            applyBarRotation()
            return built
        }

        func start() {
            guard !isStopped, motion.isDeviceMotionAvailable else { return }
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            // Delivered on .main, so assumeIsolated is safe and avoids a per-frame Task hop (Swift 6).
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                guard let self, let gravity = data?.gravity else { return }
                let g = SIMD3<Double>(gravity.x, gravity.y, gravity.z)
                MainActor.assumeIsolated {
                    self.apply(gravity: g)
                }
            }
        }

        func stop() {
            isStopped = true
            motion.stopDeviceMotionUpdates()
        }

        /// Moves the light's rest anchor. Repositions immediately, so it's also live on
        /// the Simulator where CoreMotion never ticks.
        func setLightAnchor(_ anchor: SIMD2<Double>) {
            guard anchor != lightAnchor else { return }
            lightAnchor = anchor
            positionLight()
        }

        /// Base rotation from the demo's Rotation X/Y sliders; motion leans on top of it.
        func setBaseRotation(_ degrees: SIMD2<Double>) {
            guard degrees != baseRotation else { return }
            baseRotation = degrees
            applyBarRotation()
        }

        private func apply(gravity: SIMD3<Double>) {
            smoothedGravity.x = GoldBarLighting.smoothed(previous: smoothedGravity.x, target: gravity.x, factor: 0.18)
            smoothedGravity.y = GoldBarLighting.smoothed(previous: smoothedGravity.y, target: gravity.y, factor: 0.18)
            // Dead-band: sensor noise never settles, so without this the scene is dirtied —
            // and re-rendered — 60 times a second even while the phone is held still.
            // Skipping sub-perceptual deltas lets the view idle (battery, thermals).
            let delta = max(abs(smoothedGravity.x - lastAppliedGravity.x),
                            abs(smoothedGravity.y - lastAppliedGravity.y))
            guard delta > 0.0025 else { return }
            lastAppliedGravity = smoothedGravity
            motionRotation = GoldBarLighting.barRotationDegrees(gravity: smoothedGravity)
            applyBarRotation()
        }

        /// Direct sets — wrapping these in SCNTransaction animations at 60Hz piles up
        /// overlapping interpolators and drops frames; the low-pass filter already smooths.
        private func applyBarRotation() {
            guard let bundle else { return }  // scene not built yet; reapplied on build
            let yaw = (baseRotation.x + motionRotation.x) * .pi / 180
            let pitch = (baseRotation.y + motionRotation.y) * .pi / 180
            bundle.barNode.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)
        }

        private func positionLight() {
            guard let bundle else { return }  // scene not built yet; reapplied on build
            let direction = GoldBarLighting.lightDirection(anchor: lightAnchor)
            bundle.keyLightNode.position = SCNVector3(Float(direction.x), Float(direction.y), Float(direction.z))
            bundle.keyLightNode.look(at: SCNVector3Zero)
        }
    }
}
