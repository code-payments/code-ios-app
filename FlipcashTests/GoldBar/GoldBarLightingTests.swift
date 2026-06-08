import Testing
import simd
@testable import Flipcash

@Suite("GoldBarLighting")
struct GoldBarLightingTests {

    @Test("Level device points the key light up-and-forward, centered")
    func lightDirection_level_centeredForward() {
        let d = GoldBarLighting.lightDirection(roll: 0, pitch: 0)
        #expect(abs(d.x) < 0.0001)   // centered horizontally
        #expect(d.z > 0)             // in front of the bar
        #expect(d.y > 0)             // slightly above
        #expect(abs(simd_length(d) - 1) < 0.0001) // normalized
    }

    @Test("Rolling right pushes the highlight to +X; left to -X")
    func lightDirection_roll_shiftsHorizontally() {
        #expect(GoldBarLighting.lightDirection(roll: 0.3, pitch: 0).x > 0)
        #expect(GoldBarLighting.lightDirection(roll: -0.3, pitch: 0).x < 0)
    }

    @Test("Pitching forward raises the highlight on Y")
    func lightDirection_pitch_shiftsVertically() {
        let level = GoldBarLighting.lightDirection(roll: 0, pitch: 0).y
        #expect(GoldBarLighting.lightDirection(roll: 0, pitch: 0.3).y > level)
    }

    @Test("Environment rotation scales monotonically with tilt")
    func environmentRotation_scalesWithTilt() {
        let small = GoldBarLighting.environmentRotation(roll: 0.1, pitch: 0)
        let large = GoldBarLighting.environmentRotation(roll: 0.5, pitch: 0)
        #expect(large.yaw > small.yaw)
    }

    @Test("Extreme tilt is clamped so the highlight stays on the bar")
    func lightDirection_extremeTilt_clamped() {
        let extreme = GoldBarLighting.lightDirection(roll: 5.0, pitch: 0).x
        let atClamp = GoldBarLighting.lightDirection(roll: 1.2, pitch: 0).x
        #expect(abs(extreme - atClamp) < 0.0001)
    }

    @Test("Smoothing moves a fixed fraction toward the target")
    func smoothed_movesTowardTarget() {
        #expect(GoldBarLighting.smoothed(previous: 0, target: 1, factor: 0.25) == 0.25)
        #expect(GoldBarLighting.smoothed(previous: 1, target: 1, factor: 0.25) == 1)
    }
}
