import SwiftUI
import SceneKit
import CoreMotion

/// Hosts the gold-bar SCNView and drives the light + environment from device tilt.
/// The bar and camera never move; only the light orientation and environment rotation change.
struct GoldBarSceneView: UIViewRepresentable {

    let qrPayload: String
    var lightIntensity: Double
    var environmentIntensity: Double
    var relief: Double
    /// Rest position of the key light; tilt sweeps the highlight around this anchor.
    var lightAnchor: SIMD2<Double>
    /// Bar rotation in degrees: x turns left/right, y tilts up/down; zero faces the user dead-on.
    var barRotationDegrees: SIMD2<Double>
    /// Called once the scene is attached and renderable — the placeholder above can fade out.
    var onSceneReady: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(qrPayload: qrPayload) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        // Attaching the scene is deferred until `prepare` has compiled its shaders and
        // uploaded textures off the main thread — attached up front, the first frame
        // blocks presentation on the whole compile (seconds on a cold launch).
        let coordinator = context.coordinator
        let onReady = onSceneReady
        Task {
            await withCheckedContinuation { continuation in
                view.prepare([coordinator.bundle.scene]) { _ in
                    continuation.resume()
                }
            }
            view.scene = coordinator.bundle.scene
            coordinator.start()
            onReady()
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Scalars only — never reassign `.contents` here or the baked roughness/normal maps are lost.
        // Each write is guarded so unrelated SwiftUI updates don't dirty the SceneKit scene.
        let coordinator = context.coordinator
        let bundle = coordinator.bundle
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
        if coordinator.appliedBarRotation != barRotationDegrees {
            coordinator.appliedBarRotation = barRotationDegrees
            bundle.barNode.eulerAngles = SCNVector3(
                Float(barRotationDegrees.y * .pi / 180),
                Float(barRotationDegrees.x * .pi / 180),
                0
            )
        }
        coordinator.setLightAnchor(lightAnchor)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        let bundle: GoldBarScene.Bundle
        var appliedLightIntensity: Double?
        var appliedEnvironmentIntensity: Double?
        var appliedRelief: Double?
        var appliedBarRotation: SIMD2<Double>?

        private let motion = CMMotionManager()
        // Start near the neutral held attitude so the first frame is already centered.
        private var smoothedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)
        private var lightAnchor: SIMD2<Double>?

        init(qrPayload: String) {
            if let cached = GoldBarScene.cachedTextures, cached.payload == qrPayload {
                bundle = GoldBarScene.make(textures: cached.textures)
            } else {
                // Milliseconds-cheap preview maps so presentation never waits on the bake;
                // the full-resolution set fades in when the background bake completes.
                bundle = GoldBarScene.make(textures: GoldBarMaterialBaker.bake(.preview(qrPayload: qrPayload)))
                bakeFullTextures(qrPayload: qrPayload)
            }
        }

        private func bakeFullTextures(qrPayload: String) {
            let material = bundle.material
            Task {
                let textures = await GoldBarScene.fullTextures(qrPayload: qrPayload)
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                material.diffuse.contents = textures.albedo
                material.normal.contents = textures.normal
                material.roughness.contents = textures.roughness
                SCNTransaction.commit()
            }
        }

        // start() can arrive after stop() when the cover is dismissed mid-prepare —
        // motion must not be left running on a torn-down view.
        private var isStopped = false

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

        /// Moves the light's rest anchor; tilt keeps sweeping around it. Repositions
        /// immediately, so it's also live on the Simulator where CoreMotion never ticks.
        func setLightAnchor(_ anchor: SIMD2<Double>) {
            guard anchor != lightAnchor else { return }
            lightAnchor = anchor
            positionLight(for: smoothedGravity)
        }

        private var lastAppliedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)

        private func apply(gravity: SIMD3<Double>) {
            smoothedGravity.x = GoldBarLighting.smoothed(previous: smoothedGravity.x, target: gravity.x, factor: 0.18)
            smoothedGravity.y = GoldBarLighting.smoothed(previous: smoothedGravity.y, target: gravity.y, factor: 0.18)
            // Dead-band: sensor noise never settles, so without this the scene is dirtied —
            // and re-rendered — 60 times a second even while the phone is held still.
            // Skipping sub-perceptual deltas lets the view idle (battery, thermals).
            let delta = max(abs(smoothedGravity.x - lastAppliedGravity.x),
                            abs(smoothedGravity.y - lastAppliedGravity.y))
            guard delta > 0.0025 else { return }
            positionLight(for: smoothedGravity)
        }

        /// Direct sets — wrapping these in SCNTransaction animations at 60Hz piles up
        /// overlapping interpolators and drops frames; the low-pass filter already smooths.
        private func positionLight(for gravity: SIMD3<Double>) {
            lastAppliedGravity = gravity
            let anchor = lightAnchor ?? SIMD2(0, GoldBarLighting.restElevation)
            let direction = GoldBarLighting.lightDirection(gravity: gravity, anchor: anchor)
            let envRotation = GoldBarLighting.environmentRotation(gravity: gravity)
            bundle.keyLightNode.position = SCNVector3(Float(direction.x), Float(direction.y), Float(direction.z))
            bundle.keyLightNode.look(at: SCNVector3Zero)
            let yaw = SCNMatrix4MakeRotation(Float(envRotation.yaw), 0, 1, 0)
            let pitch = SCNMatrix4MakeRotation(Float(envRotation.pitch), 1, 0, 0)
            bundle.scene.lightingEnvironment.contentsTransform = SCNMatrix4Mult(yaw, pitch)
        }
    }
}
