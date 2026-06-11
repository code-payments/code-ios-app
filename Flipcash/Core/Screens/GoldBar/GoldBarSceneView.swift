import SwiftUI
import SceneKit
import CoreMotion

/// Hosts the gold-bar SCNView. Device tilt leans the bar slightly (sweeping its
/// reflections); the key light stays fixed at its anchor. Camera never moves.
struct GoldBarSceneView: UIViewRepresentable {

    let codeData: Data
    /// Engraved lines stacked on the upper face (the amount, in production).
    let stampLines: [String]
    /// Engraved serial line (the USDF public key, in production).
    let serial: String
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

    func makeCoordinator() -> Coordinator {
        Coordinator(codeData: codeData, stampLines: stampLines, serial: serial)
    }

    func makeUIView(context: Context) -> UIView {
        // An empty container comes back immediately: every SceneKit/Metal step (view
        // creation, shader compile, scene attach) lands main-thread hitches, so all of
        // it is deferred past the cover transition, where the placeholder hides it.
        let container = UIView()
        container.backgroundColor = .clear
        let coordinator = context.coordinator
        let onReady = onSceneReady
        Task {
            // Past the first presentation frames, so the code render (~15ms on main)
            // can't join the tap; the bake itself runs off-main from here.
            try? await Task.sleep(for: .milliseconds(150))
            coordinator.startEarlyBake()
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))  // cover transition runs ~0.5s
            guard !coordinator.isStopped else { return }

            let bundle = coordinator.buildSceneIfNeeded()
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

        private let codeData: Data
        private let stampLines: [String]
        private let serial: String
        private let motion = CMMotionManager()
        // Start near the neutral held attitude so the first frame is already centered.
        private var smoothedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)
        private var lastAppliedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)
        private var lightAnchor = GoldBarLighting.restAnchor
        private var baseRotation = SIMD2<Double>(0, 0)
        private var motionRotation = SIMD2<Double>(0, 0)

        init(codeData: Data, stampLines: [String], serial: String) {
            self.codeData = codeData
            self.stampLines = stampLines
            self.serial = serial
        }

        private var codeImage: UIImage?

        private var textureKey: GoldBarScene.TextureKey {
            GoldBarScene.TextureKey(payload: codeData, stampLines: stampLines, serial: serial)
        }

        private func renderCodeIfNeeded() -> UIImage {
            if let codeImage { return codeImage }
            let code = GoldBarCodeRenderer.image(for: codeData, side: 480)
            codeImage = code
            return code
        }

        /// Starts the full-resolution bake before the scene exists — the bake is
        /// off-main, so by the time the deferred attach runs, the texture cache is
        /// usually already full quality and the preview phase is skipped entirely.
        func startEarlyBake() {
            guard !isStopped else { return }
            let key = textureKey
            guard GoldBarScene.cachedTextures?.key != key else { return }
            let code = renderCodeIfNeeded()
            Task { _ = await GoldBarScene.fullTextures(key: key, code: code) }
        }

        /// Builds the scene on first call — kept out of init so presenting the cover does
        /// no scene work at all; the deferred task behind the placeholder calls this.
        func buildSceneIfNeeded() -> GoldBarScene.Bundle {
            if let bundle { return bundle }
            let key = textureKey
            let built: GoldBarScene.Bundle
            if let cached = GoldBarScene.cachedTextures, cached.key == key {
                built = GoldBarScene.make(textures: cached.textures)
                bundle = built
            } else {
                // The Kik code renders once on the main actor (ImageRenderer); the
                // milliseconds-cheap preview maps mean the bar never waits on the bake,
                // and the full-resolution set arrives when the background bake completes
                // (shared with any bake startEarlyBake already has in flight).
                let code = renderCodeIfNeeded()
                built = GoldBarScene.make(textures: GoldBarMaterialBaker.bake(
                    .preview(code: code, stampLines: stampLines, serial: serial)
                ))
                bundle = built
                bakeFullTextures(key: key, code: code)
            }
            positionLight()
            applyBarRotation()
            return built
        }

        private func bakeFullTextures(key: GoldBarScene.TextureKey, code: UIImage) {
            guard let material = bundle?.material else { return }
            Task { [weak self] in
                let textures = await GoldBarScene.fullTextures(key: key, code: code)
                // Upload the new maps to the GPU off the main thread first, so the swap
                // below is a cheap pointer change instead of a mid-frame texture upload.
                if let view = self?.scnView {
                    let staging = SCNMaterial()
                    staging.diffuse.contents = textures.albedo
                    staging.normal.contents = textures.normal
                    staging.roughness.contents = textures.roughness
                    await withCheckedContinuation { continuation in
                        view.prepare([staging]) { _ in continuation.resume() }
                    }
                }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                material.diffuse.contents = textures.albedo
                material.normal.contents = textures.normal
                material.roughness.contents = textures.roughness
                SCNTransaction.commit()
            }
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
