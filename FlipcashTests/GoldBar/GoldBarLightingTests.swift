import Testing
import simd
@testable import Flipcash

@Suite("GoldBarLighting")
struct GoldBarLightingTests {

    /// Phone held up to view it (top up, leaned back a little) — the centered rest attitude.
    private static let neutral = SIMD3<Double>(0, GoldBarLighting.neutralGravityY, -0.5)

    @Test("Light direction follows its anchor and stays normalized")
    func lightDirection_followsAnchor() {
        let rest = GoldBarLighting.lightDirection(anchor: GoldBarLighting.restAnchor)
        #expect(abs(rest.x) < 0.0001)  // centered horizontally
        #expect(rest.y > 0)            // above the bar
        #expect(rest.z > 0)            // in front of the bar
        #expect(abs(simd_length(rest) - 1) < 0.0001)

        let right = GoldBarLighting.lightDirection(anchor: SIMD2(0.8, GoldBarLighting.restAnchor.y))
        #expect(right.x > 0)
    }

    @Test("Neutral held attitude leaves the bar facing the user")
    func barRotation_neutral_isZero() {
        let rotation = GoldBarLighting.barRotationDegrees(gravity: Self.neutral)
        #expect(abs(rotation.x) < 0.0001)
        #expect(abs(rotation.y) < 0.0001)
    }

    @Test("Rolling tilts the bar's yaw; leaning tilts its pitch")
    func barRotation_followsTilt() {
        let rolled = GoldBarLighting.barRotationDegrees(gravity: SIMD3(0.3, GoldBarLighting.neutralGravityY, -0.5))
        #expect(rolled.x > 0)
        #expect(abs(rolled.y) < 0.0001)

        let leanedBack = GoldBarLighting.barRotationDegrees(gravity: SIMD3(0, -0.5, -0.8))
        #expect(leanedBack.y > 0)
    }

    @Test("Rotation is clamped so the bar only leans slightly")
    func barRotation_clamped() {
        let extreme = GoldBarLighting.barRotationDegrees(gravity: SIMD3(1.0, 0, 0))
        #expect(extreme.x == GoldBarLighting.maxYawDegrees)
        #expect(extreme.y == GoldBarLighting.maxPitchDegrees)
    }

    @Test("Smoothing moves a fixed fraction toward the target")
    func smoothed_movesTowardTarget() {
        #expect(GoldBarLighting.smoothed(previous: 0, target: 1, factor: 0.25) == 0.25)
        #expect(GoldBarLighting.smoothed(previous: 1, target: 1, factor: 0.25) == 1)
    }
}
