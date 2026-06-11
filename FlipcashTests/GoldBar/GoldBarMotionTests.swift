import Testing
import simd
@testable import Flipcash

@Suite("GoldBarMotion")
struct GoldBarMotionTests {

    /// Phone held up to view it (top up, leaned back a little) — the centered rest attitude.
    private static let neutral = SIMD3<Double>(0, GoldBarMotion.neutralGravityY, -0.5)

    @Test("Neutral held attitude leaves the bar facing the user")
    func barRotation_neutral_isZero() {
        let rotation = GoldBarMotion.barRotationDegrees(gravity: Self.neutral)
        #expect(abs(rotation.x) < 0.0001)
        #expect(abs(rotation.y) < 0.0001)
    }

    @Test("Rolling tilts the bar's yaw; leaning tilts its pitch, mirroring the phone")
    func barRotation_followsTilt() {
        let rolled = GoldBarMotion.barRotationDegrees(gravity: SIMD3(0.3, GoldBarMotion.neutralGravityY, -0.5))
        #expect(rolled.x > 0)
        #expect(abs(rolled.y) < 0.0001)

        // Phone tilted forward (top away, toward flat) → the bar's top leans away too.
        let tiltedForward = GoldBarMotion.barRotationDegrees(gravity: SIMD3(0, -0.5, -0.8))
        #expect(tiltedForward.y < 0)
    }

    @Test("Rotation is clamped so the bar only leans slightly")
    func barRotation_clamped() {
        // Rolled hard right and tilted fully flat — both axes hit their clamps.
        let extreme = GoldBarMotion.barRotationDegrees(gravity: SIMD3(1.0, 0, 0))
        #expect(extreme.x == GoldBarMotion.maxYawDegrees)
        #expect(extreme.y == -GoldBarMotion.maxPitchDegrees)
    }

    @Test("Smoothing moves a fixed fraction toward the target")
    func smoothed_movesTowardTarget() {
        #expect(GoldBarMotion.smoothed(previous: 0, target: 1, factor: 0.25) == 0.25)
        #expect(GoldBarMotion.smoothed(previous: 1, target: 1, factor: 0.25) == 1)
    }
}
