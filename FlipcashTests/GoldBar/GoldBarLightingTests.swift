import Testing
import simd
@testable import Flipcash

@Suite("GoldBarLighting")
struct GoldBarLightingTests {

    /// Phone held up to view it (top up, leaned back a little) — the centered rest attitude.
    private static let neutral = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)

    @Test("Neutral held attitude points the key light up-and-forward, centered")
    func lightDirection_neutralHold_centeredForward() {
        let d = GoldBarLighting.lightDirection(gravity: Self.neutral)
        #expect(abs(d.x) < 0.0001)   // centered horizontally
        #expect(d.z > 0)             // in front of the bar
        #expect(d.y > 0)             // slightly above
        #expect(abs(simd_length(d) - 1) < 0.0001) // normalized
    }

    @Test("Rolling right pushes the highlight to +X; left to -X")
    func lightDirection_roll_shiftsHorizontally() {
        let right = GoldBarLighting.lightDirection(gravity: SIMD3(0.3, GoldBarLighting.neutralGravityY, -0.5))
        let left = GoldBarLighting.lightDirection(gravity: SIMD3(-0.3, GoldBarLighting.neutralGravityY, -0.5))
        #expect(right.x > 0)
        #expect(left.x < 0)
    }

    @Test("Leaning the top back toward flat raises the highlight on Y")
    func lightDirection_pitchBack_raisesHighlight() {
        let neutralY = GoldBarLighting.lightDirection(gravity: Self.neutral).y
        // gravity.y closer to 0 means the phone is leaned back toward flat.
        let leanedBack = GoldBarLighting.lightDirection(gravity: SIMD3(0, -0.5, -0.5)).y
        #expect(leanedBack > neutralY)
    }

    @Test("Holding more upright lowers the highlight on Y")
    func lightDirection_moreUpright_lowersHighlight() {
        let neutralY = GoldBarLighting.lightDirection(gravity: Self.neutral).y
        let upright = GoldBarLighting.lightDirection(gravity: SIMD3(0, -0.98, -0.1)).y
        #expect(upright < neutralY)
    }

    @Test("Environment rotation scales monotonically with left/right tilt")
    func environmentRotation_scalesWithTilt() {
        let small = GoldBarLighting.environmentRotation(gravity: SIMD3(0.1, GoldBarLighting.neutralGravityY, -0.5))
        let large = GoldBarLighting.environmentRotation(gravity: SIMD3(0.5, GoldBarLighting.neutralGravityY, -0.5))
        #expect(large.yaw > small.yaw)
    }

    @Test("Extreme tilt is clamped so the highlight stays on the bar")
    func lightDirection_extremeTilt_clamped() {
        let extreme = GoldBarLighting.lightDirection(gravity: SIMD3(1.0, GoldBarLighting.neutralGravityY, -0.5)).x
        let atClamp = GoldBarLighting.lightDirection(gravity: SIMD3(0.7, GoldBarLighting.neutralGravityY, -0.5)).x
        #expect(abs(extreme - atClamp) < 0.0001)
    }

    @Test("Smoothing moves a fixed fraction toward the target")
    func smoothed_movesTowardTarget() {
        #expect(GoldBarLighting.smoothed(previous: 0, target: 1, factor: 0.25) == 0.25)
        #expect(GoldBarLighting.smoothed(previous: 1, target: 1, factor: 0.25) == 1)
    }
}
