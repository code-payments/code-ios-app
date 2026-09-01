import XCTest
import FlipcashCore   // the app's Base58 (public enum Base58)

/// GATE: this repo's Base58 must reproduce the canonical cross-platform fixtures exactly (encode and
/// decode). The Android repo asserts the identical fixtures against its Base58 — matching on both
/// sides guarantees the apps agree on address/key encoding. Anchored to the Solana all-ones address.
final class Base58VectorTests: XCTestCase {

    struct Vector: Decodable { let name, bytes, base58: String }
    struct Fixture: Decodable { let vectors: [Vector] }

    func testBase58MatchesCanonicalVectors() throws {
        let url = Bundle.module.url(forResource: "base58", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url, "base58.json fixture missing"))
        let vectors = try JSONDecoder().decode(Fixture.self, from: data).vectors
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        for v in vectors {
            let bytes = [UInt8](hex: v.bytes)
            XCTAssertEqual(Base58.fromBytes(bytes), v.base58, "encode mismatch for \(v.name)")
            XCTAssertEqual([UInt8](Base58.toBytes(v.base58)), bytes, "decode mismatch for \(v.name)")
        }
    }
}

private extension Array where Element == UInt8 {
    init(hex: String) {
        var out = [UInt8](); out.reserveCapacity(hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex, let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) {
            out.append(UInt8(hex[i..<j], radix: 16) ?? 0); i = j
        }
        self = out
    }
}
