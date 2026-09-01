import XCTest
import FlipcashCore
import BigDecimal

/// GATE: this repo's discrete bonding curve must reproduce the canonical cross-platform fixtures
/// exactly. The Android repo asserts the identical fixtures — matching on both sides guarantees the
/// apps price trades identically (a divergence here = one platform computing a different cost/amount
/// than the chain expects). Ground truth = the on-chain Rust curve; both apps load the same u128 tables.
final class DiscreteBondingCurveVectorTests: XCTestCase {

    struct Vector: Decodable {
        let name, spotPrice, value: String
        let currentSupply, tokens: Int
    }
    struct Fixture: Decodable { let vectors: [Vector] }

    func testCurveMatchesCanonicalVectors() throws {
        let url = Bundle.module.url(forResource: "curve", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url, "curve.json fixture missing"))
        let vectors = try JSONDecoder().decode(Fixture.self, from: data).vectors
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        let curve = DiscreteBondingCurve()
        for v in vectors {
            let spot = try XCTUnwrap(curve.spotPrice(at: v.currentSupply), "spotPrice nil for \(v.name)")
            assertEqual(spot, BigDecimal(v.spotPrice), "spotPrice \(v.name)")

            let value = try XCTUnwrap(curve.tokensToValue(currentSupply: v.currentSupply, tokens: v.tokens),
                                      "tokensToValue nil for \(v.name)")
            assertEqual(value, BigDecimal(v.value), "tokensToValue \(v.name)")
        }
    }

    struct FractionalVector: Decodable { let name, currentSupply, tokens, value: String }
    struct FractionalFixture: Decodable { let vectors: [FractionalVector] }

    /// Fractional (sell-path) + rounding-tie cases via the BigDecimal overload — the residual
    /// divergence risk (iOS rounding-context subtraction vs Android exact subtract).
    func testCurveFractionalMatchesCanonicalVectors() throws {
        let url = Bundle.module.url(forResource: "curve_fractional", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url, "curve_fractional.json fixture missing"))
        let vectors = try JSONDecoder().decode(FractionalFixture.self, from: data).vectors
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        let curve = DiscreteBondingCurve()
        for v in vectors {
            let value = try XCTUnwrap(
                curve.tokensToValue(currentSupply: BigDecimal(v.currentSupply), tokens: BigDecimal(v.tokens)),
                "tokensToValue nil for \(v.name)")
            assertEqual(value, BigDecimal(v.value), "tokensToValue \(v.name)")
        }
    }

    /// Scale-insensitive numeric equality (avoids BigDecimal scale/trailing-zero artifacts).
    private func assertEqual(_ a: BigDecimal, _ b: BigDecimal, _ msg: String) {
        XCTAssertFalse(a < b || b < a, "\(msg): got \(a), expected \(b)")
    }
}
