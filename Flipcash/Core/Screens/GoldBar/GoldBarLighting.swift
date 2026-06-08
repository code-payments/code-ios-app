import Foundation
import simd

/// Pure mapping from the device's gravity vector to the gold bar's key-light direction
/// and environment rotation. Referenced to a *held* viewing attitude (not flat-on-desk),
/// so the highlight is centered when the phone is picked up and sweeps as you tilt from there.
/// No SceneKit state — deterministic and unit-testable.
nonisolated enum GoldBarLighting {

    /// How far a unit of left/right tilt (gravity.x) pushes the highlight horizontally.
    static let lateralGain: Double = 2.4
    /// How far a unit of forward/back tilt (gravity.y vs neutral) pushes the highlight vertically.
    static let verticalGain: Double = 1.6
    /// Environment yaw rotation per unit of left/right tilt (radians) — sweeps the broad sheen.
    static let envYawGain: Double = 0.9
    /// Environment pitch rotation per unit of forward/back tilt (radians).
    static let envPitchGain: Double = 0.7
    /// gravity.y when the phone is held up to view it (top up, leaned back a little).
    /// The light is centered at this attitude — NOT when the phone lies flat (gravity.y == 0).
    static let neutralGravityY: Double = -0.85
    /// Resting elevation of the key light at the neutral held attitude (gives an upper sheen).
    static let restElevation: Double = 0.35
    /// Keep the highlight on the bar by clamping how far tilt can push it.
    static let horizontalClamp: Double = 1.5
    static let verticalClamp: Double = 1.4

    /// Unit direction the key light sits in, for the device's gravity vector (CoreMotion device frame).
    /// Level-held → up-and-forward, centered; rolling moves it horizontally; pitching moves it vertically.
    static func lightDirection(gravity: SIMD3<Double>) -> SIMD3<Double> {
        let x = clamp(gravity.x * lateralGain, horizontalClamp)
        let y = restElevation + clamp((gravity.y - neutralGravityY) * verticalGain, verticalClamp)
        let z = 1.0
        return simd_normalize(SIMD3(x, y, z))
    }

    /// Yaw/pitch (radians) to rotate the lighting environment so reflections sweep with tilt.
    static func environmentRotation(gravity: SIMD3<Double>) -> (yaw: Double, pitch: Double) {
        (yaw: clamp(gravity.x, 1) * envYawGain,
         pitch: clamp(gravity.y - neutralGravityY, 1) * envPitchGain)
    }

    /// Exponential smoothing toward `target`; `factor` in 0...1 (higher = snappier).
    static func smoothed(previous: Double, target: Double, factor: Double) -> Double {
        previous + (target - previous) * factor
    }

    private static func clamp(_ value: Double, _ limit: Double) -> Double {
        min(max(value, -limit), limit)
    }
}
