import Foundation
import simd

/// Pure mapping from device tilt to the gold bar's key-light direction and
/// environment rotation. No SceneKit state — deterministic and unit-testable.
nonisolated enum GoldBarLighting {

    /// How far a unit of device tilt (radians) pushes the key light.
    static let lightTiltGain: Double = 1.2
    /// How far a unit of device tilt (radians) rotates the reflected environment.
    static let envTiltGain: Double = 0.9
    /// Tilt magnitude (radians) beyond which we stop chasing, keeping the highlight on the bar.
    static let tiltClamp: Double = 1.2
    /// Resting elevation of the key light at a level device.
    static let restElevation: Double = 0.35

    /// Unit direction the key light sits in, in scene space, for a device tilt.
    /// Level → up-and-forward and centered; roll moves it horizontally; pitch vertically.
    static func lightDirection(roll: Double, pitch: Double) -> SIMD3<Double> {
        let x = sin(clamp(roll) * lightTiltGain)
        let y = restElevation + sin(clamp(pitch) * lightTiltGain)
        let z = 1.0
        return simd_normalize(SIMD3(x, y, z))
    }

    /// Yaw/pitch (radians) to rotate the lighting environment so reflections sweep with tilt.
    static func environmentRotation(roll: Double, pitch: Double) -> (yaw: Double, pitch: Double) {
        (yaw: clamp(roll) * envTiltGain, pitch: clamp(pitch) * envTiltGain)
    }

    /// Exponential smoothing toward `target`; `factor` in 0...1 (higher = snappier).
    static func smoothed(previous: Double, target: Double, factor: Double) -> Double {
        previous + (target - previous) * factor
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, -tiltClamp), tiltClamp)
    }
}
