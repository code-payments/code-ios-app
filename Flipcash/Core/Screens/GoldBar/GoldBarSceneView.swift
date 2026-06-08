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

    func makeCoordinator() -> Coordinator { Coordinator(qrPayload: qrPayload) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.bundle.scene
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.allowsCameraControl = false
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Scalars only — never reassign `.contents` here or the baked roughness/normal maps are lost.
        let bundle = context.coordinator.bundle
        bundle.keyLightNode.light?.intensity = CGFloat(lightIntensity)
        bundle.scene.lightingEnvironment.intensity = CGFloat(environmentIntensity)
        bundle.material.normal.intensity = CGFloat(relief)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        let bundle: GoldBarScene.Bundle
        private let motion = CMMotionManager()
        // Start near the neutral held attitude so the first frame is already centered.
        private var smoothedGravity = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)

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

        private func apply(gravity: SIMD3<Double>) {
            smoothedGravity.x = GoldBarLighting.smoothed(previous: smoothedGravity.x, target: gravity.x, factor: 0.18)
            smoothedGravity.y = GoldBarLighting.smoothed(previous: smoothedGravity.y, target: gravity.y, factor: 0.18)

            let direction = GoldBarLighting.lightDirection(gravity: smoothedGravity)
            let envRotation = GoldBarLighting.environmentRotation(gravity: smoothedGravity)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.12
            bundle.keyLightNode.position = SCNVector3(Float(direction.x), Float(direction.y), Float(direction.z))
            bundle.keyLightNode.look(at: SCNVector3Zero)
            let yaw = SCNMatrix4MakeRotation(Float(envRotation.yaw), 0, 1, 0)
            let pitchM = SCNMatrix4MakeRotation(Float(envRotation.pitch), 1, 0, 0)
            bundle.scene.lightingEnvironment.contentsTransform = SCNMatrix4Mult(yaw, pitchM)
            SCNTransaction.commit()
        }
    }
}
