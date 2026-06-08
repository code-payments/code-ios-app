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
        private var smoothedRoll: Double = 0
        private var smoothedPitch: Double = 0

        init(qrPayload: String) {
            bundle = GoldBarScene.make(qrPayload: qrPayload)
        }

        func start() {
            guard motion.isDeviceMotionAvailable else { return }
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            // Delivered on .main, so assumeIsolated is safe and avoids a per-frame Task hop (Swift 6).
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                guard let self, let attitude = data?.attitude else { return }
                let roll = attitude.roll
                let pitch = attitude.pitch
                MainActor.assumeIsolated {
                    self.apply(roll: roll, pitch: pitch)
                }
            }
        }

        func stop() {
            motion.stopDeviceMotionUpdates()
        }

        private func apply(roll: Double, pitch: Double) {
            smoothedRoll = GoldBarLighting.smoothed(previous: smoothedRoll, target: roll, factor: 0.18)
            smoothedPitch = GoldBarLighting.smoothed(previous: smoothedPitch, target: pitch, factor: 0.18)

            let direction = GoldBarLighting.lightDirection(roll: smoothedRoll, pitch: smoothedPitch)
            let envRotation = GoldBarLighting.environmentRotation(roll: smoothedRoll, pitch: smoothedPitch)

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
