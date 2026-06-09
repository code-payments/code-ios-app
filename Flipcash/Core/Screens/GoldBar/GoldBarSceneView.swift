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
    /// Bar yaw in degrees; 0 faces the user dead-on.
    var barRotationDegrees: Double

    func makeCoordinator() -> Coordinator { Coordinator(qrPayload: qrPayload) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.bundle.scene
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        context.coordinator.start()
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
            bundle.barNode.eulerAngles.y = Float(barRotationDegrees * .pi / 180)
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
        var appliedBarRotation: Double?

        private let motion = CMMotionManager()
        // Start near the neutral held attitude so the first frame is already centered.
        private var smoothedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)
        private var lightAnchor: SIMD2<Double>?

        init(qrPayload: String) {
            bundle = GoldBarScene.make(qrPayload: qrPayload)
        }

        func start() {
            guard motion.isDeviceMotionAvailable else { return }
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
            motion.stopDeviceMotionUpdates()
        }

        /// Moves the light's rest anchor; tilt keeps sweeping around it. Repositions
        /// immediately, so it's also live on the Simulator where CoreMotion never ticks.
        func setLightAnchor(_ anchor: SIMD2<Double>) {
            guard anchor != lightAnchor else { return }
            lightAnchor = anchor
            positionLight(for: smoothedGravity)
        }

        private func apply(gravity: SIMD3<Double>) {
            smoothedGravity.x = GoldBarLighting.smoothed(previous: smoothedGravity.x, target: gravity.x, factor: 0.18)
            smoothedGravity.y = GoldBarLighting.smoothed(previous: smoothedGravity.y, target: gravity.y, factor: 0.18)
            positionLight(for: smoothedGravity)
        }

        /// Direct sets — wrapping these in SCNTransaction animations at 60Hz piles up
        /// overlapping interpolators and drops frames; the low-pass filter already smooths.
        private func positionLight(for gravity: SIMD3<Double>) {
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
