import Testing
import simd
@testable import Flipcash

@MainActor
@Suite("GoldBarScene")
struct GoldBarSceneTests {

    @Test("Light direction follows its anchor and stays normalized")
    func lightDirection_followsAnchor() {
        let rest = GoldBarScene.lightDirection(anchor: GoldBarTuning.standard.lightAnchor)
        #expect(abs(rest.x) < 0.0001)  // centered horizontally
        #expect(rest.y > 0)            // above the bar
        #expect(rest.z > 0)            // in front of the bar
        #expect(abs(simd_length(rest) - 1) < 0.0001)

        let right = GoldBarScene.lightDirection(anchor: SIMD2(0.8, GoldBarTuning.standard.lightAnchor.y))
        #expect(right.x > 0)
    }
}
