import SceneKit
import UIKit
import CoreMotion
import FlipcashUI

/// The session-long home of the gold bar's SceneKit machinery: one SCNView and
/// one scene, created at warm-up and reused for every presentation. Presenting
/// swaps the baked maps in (pointer changes — they're GPU-resident via
/// `prepare`), so nothing is allocated, compiled, or first-rendered on the
/// presentation path. Presenters adopt/release with an owner token; a stale
/// owner can never tear down the current adoption.
@MainActor
final class GoldBarSceneHost {

    static let shared = GoldBarSceneHost()

    private(set) var appliedKey: GoldBarTextureStore.Key?
    private(set) var ownerToken: ObjectIdentifier?

    private let store: GoldBarTextureStore
    private var view: SCNView?
    private var bundle: GoldBarScene.Bundle?
    private var warmTask: Task<Void, Never>?
    private var tuning = GoldBarTuning.standard

    private let motion = CMMotionManager()
    private var smoothedGravity = SIMD3<Double>(0, GoldBarMotion.neutralGravityY, -0.5)
    private var lastAppliedGravity = SIMD3<Double>(0, GoldBarMotion.neutralGravityY, -0.5)
    private var motionRotation = SIMD2<Double>(0, 0)

    init(store: GoldBarTextureStore = .shared) {
        self.store = store
    }

    /// Idempotent; call when the scan screen settles. Builds the view and a
    /// placeholder-content scene so every Metal pipeline the real bar needs is
    /// compiled long before the first presentation.
    func warmUpIfNeeded() {
        guard warmTask == nil else { return }
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        // 2x is visually indistinguishable on a smooth metal surface and cuts
        // fragment/bandwidth work ~2.25x; the etched code must still scan.
        view.contentScaleFactor = min(2, view.traitCollection.displayScale)
        self.view = view
        warmTask = Task {
            let code = GoldBarCodeRenderer.image(for: .placeholder35, side: 64)
            let textures = GoldBarMaterialBaker.bake(GoldBarMaterialBaker.Config(
                pixelSize: CGSize(width: 96, height: 166),
                code: code,
                stampLines: ["0"],
                serial: "0",
                scratchCount: 0
            ))
            let bundle = GoldBarScene.make(textures: textures)
            await withCheckedContinuation { continuation in
                view.prepare([bundle.scene]) { _ in continuation.resume() }
            }
            view.scene = bundle.scene
            self.bundle = bundle
        }
    }

    /// Swaps the bar's content to `key` and returns the pooled view, or nil if
    /// another presenter adopted the host while this one was waiting.
    func adopt(key: GoldBarTextureStore.Key, tuning: GoldBarTuning, token: ObjectIdentifier) async -> SCNView? {
        warmUpIfNeeded()
        ownerToken = token
        // Set before any suspension: `apply(_:token:)` calls arriving while the
        // adoption is in flight (demo sliders) must win over the creation-time value.
        self.tuning = tuning
        await warmTask?.value
        guard ownerToken == token else { return nil }

        let textures = await store.textures(for: key)
        guard ownerToken == token, let view, let bundle else { return nil }

        if appliedKey != key {
            // GPU-upload the new maps via a staging material first, so the swap
            // on the live material is a pointer change, not a mid-frame upload.
            let staging = SCNMaterial()
            staging.diffuse.contents = textures.albedo
            staging.normal.contents = textures.normal
            staging.roughness.contents = textures.roughness
            await withCheckedContinuation { continuation in
                view.prepare([staging]) { _ in continuation.resume() }
            }
            guard ownerToken == token else { return nil }
            bundle.material.diffuse.contents = textures.albedo
            bundle.material.normal.contents = textures.normal
            bundle.material.roughness.contents = textures.roughness
            appliedKey = key
        }

        resetMotionState()
        applyTuningToScene()
        applyBarRotation()
        return view
    }

    /// Detaches and quiesces the bar. Only honored from the current owner, so
    /// a dismissing presenter can't tear down the next one's adoption.
    func release(token: ObjectIdentifier) {
        guard ownerToken == token else { return }
        ownerToken = nil
        motion.stopDeviceMotionUpdates()
        view?.removeFromSuperview()
    }

    /// Scalars only — never reassign material `.contents` or the baked maps
    /// are lost. Guarded on the whole value so unrelated SwiftUI updates don't
    /// dirty the scene.
    func apply(_ new: GoldBarTuning, token: ObjectIdentifier) {
        guard ownerToken == token, new != tuning else { return }
        tuning = new
        applyTuningToScene()
        applyBarRotation()
    }

    func startMotion(token: ObjectIdentifier) {
        guard ownerToken == token, motion.isDeviceMotionAvailable else { return }
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

    /// Each presentation starts from the neutral held attitude so a previous
    /// bill's lean never carries over.
    private func resetMotionState() {
        motion.stopDeviceMotionUpdates()
        smoothedGravity = SIMD3(0, GoldBarMotion.neutralGravityY, -0.5)
        lastAppliedGravity = smoothedGravity
        motionRotation = SIMD2(0, 0)
    }

    private func applyTuningToScene() {
        guard let bundle else { return }
        bundle.keyLightNode.light?.intensity = CGFloat(tuning.lightIntensity)
        bundle.scene.lightingEnvironment.intensity = CGFloat(tuning.environmentIntensity)
        bundle.material.normal.intensity = CGFloat(tuning.relief)
        let direction = GoldBarScene.lightDirection(anchor: tuning.lightAnchor)
        bundle.keyLightNode.position = SCNVector3(Float(direction.x), Float(direction.y), Float(direction.z))
        bundle.keyLightNode.look(at: SCNVector3Zero)
    }

    private func apply(gravity: SIMD3<Double>) {
        smoothedGravity.x = GoldBarMotion.smoothed(previous: smoothedGravity.x, target: gravity.x, factor: GoldBarMotion.smoothingFactor)
        smoothedGravity.y = GoldBarMotion.smoothed(previous: smoothedGravity.y, target: gravity.y, factor: GoldBarMotion.smoothingFactor)
        // Dead-band: sensor noise never settles, so without this the scene is
        // dirtied — and re-rendered — 60 times a second even while the phone is
        // held still. Skipping sub-perceptual deltas lets the view idle.
        let delta = max(abs(smoothedGravity.x - lastAppliedGravity.x),
                        abs(smoothedGravity.y - lastAppliedGravity.y))
        guard delta > GoldBarMotion.gravityDeadBand else { return }
        lastAppliedGravity = smoothedGravity
        motionRotation = GoldBarMotion.barRotationDegrees(gravity: smoothedGravity)
        applyBarRotation()
    }

    /// Direct sets — wrapping these in SCNTransaction animations at 60Hz piles
    /// up overlapping interpolators and drops frames; the low-pass filter
    /// already smooths.
    private func applyBarRotation() {
        guard let bundle else { return }
        let yaw = (tuning.barRotationDegrees.x + motionRotation.x) * .pi / 180
        let pitch = (tuning.barRotationDegrees.y + motionRotation.y) * .pi / 180
        bundle.barNode.eulerAngles = SCNVector3(Float(pitch), Float(yaw), 0)
    }
}
