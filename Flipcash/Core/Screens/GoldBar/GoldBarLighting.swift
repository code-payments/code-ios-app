import Foundation
import simd

/// Pure mapping from the device's gravity vector to a slight rotation of the bar itself —
/// the light stays fixed and the bar leans with the device, sweeping the reflections.
/// Referenced to a *held* viewing attitude (not flat-on-desk). No SceneKit state.
nonisolated enum GoldBarLighting {

    /// gravity.y when the phone is held up to view it (top up, leaned back a little).
    /// The bar sits face-on at this attitude — NOT when the phone lies flat (gravity.y == 0).
    static let neutralGravityY: Double = -0.85
    /// Rest position of the key light (the tuned default; the demo's Light X/Y sliders move it).
    static let restAnchor = SIMD2<Double>(0, 0.36)

    /// Degrees of bar yaw per unit of left/right tilt (gravity.x).
    static let yawGain: Double = 36
    /// Degrees of bar pitch per unit of forward/back tilt (gravity.y vs neutral).
    static let pitchGain: Double = 24
    /// Big enough that the lean itself is visible (a flat bar's silhouette barely
    /// changes under ~10°, which reads as the light moving instead), small enough
    /// that the bar never turns away.
    static let maxYawDegrees: Double = 18
    static let maxPitchDegrees: Double = 12

    /// Unit direction the key light sits in, for a rest anchor (x lateral, y elevation).
    static func lightDirection(anchor: SIMD2<Double>) -> SIMD3<Double> {
        simd_normalize(SIMD3(anchor.x, anchor.y, 1))
    }

    /// Slight bar rotation (degrees) for a device tilt: x yaws left/right, y pitches up/down.
    static func barRotationDegrees(gravity: SIMD3<Double>) -> SIMD2<Double> {
        SIMD2(
            clamp(gravity.x * yawGain, maxYawDegrees),
            clamp((gravity.y - neutralGravityY) * pitchGain, maxPitchDegrees)
        )
    }

    /// Exponential smoothing toward `target`; `factor` in 0...1 (higher = snappier).
    static func smoothed(previous: Double, target: Double, factor: Double) -> Double {
        previous + (target - previous) * factor
    }

    private static func clamp(_ value: Double, _ limit: Double) -> Double {
        min(max(value, -limit), limit)
    }
}
