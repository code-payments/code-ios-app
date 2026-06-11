import Foundation
import simd

/// Pure mapping from the device's gravity vector to a slight lean of the bar —
/// the light stays fixed and the bar leans with the device, sweeping the
/// reflections. Referenced to a *held* viewing attitude (not flat-on-desk).
nonisolated enum GoldBarMotion {

    /// gravity.y when the phone is held up to view it (top up, leaned back a little).
    /// The bar sits face-on at this attitude — NOT when the phone lies flat (gravity.y == 0).
    static let neutralGravityY: Double = -0.85

    /// Degrees of bar yaw per unit of left/right tilt (gravity.x).
    static let yawGain: Double = 36
    /// Degrees of bar pitch per unit of forward/back tilt (gravity.y vs neutral).
    static let pitchGain: Double = 24
    /// Big enough that the lean itself is visible (a flat bar's silhouette barely
    /// changes under ~10°, which reads as the light moving instead), small enough
    /// that the bar never turns away.
    static let maxYawDegrees: Double = 18
    static let maxPitchDegrees: Double = 12

    /// Low-pass factor applied to each 60Hz gravity sample.
    static let smoothingFactor: Double = 0.18
    /// Sensor noise never settles; smoothed deltas below this don't re-render the scene.
    static let gravityDeadBand: Double = 0.0025

    /// Slight bar rotation (degrees) for a device tilt: x yaws left/right, y pitches up/down.
    /// The bar mirrors the phone's plane — tilt the top away and the bar leans away with it.
    static func barRotationDegrees(gravity: SIMD3<Double>) -> SIMD2<Double> {
        SIMD2(
            clamp(gravity.x * yawGain, maxYawDegrees),
            clamp((neutralGravityY - gravity.y) * pitchGain, maxPitchDegrees)
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
