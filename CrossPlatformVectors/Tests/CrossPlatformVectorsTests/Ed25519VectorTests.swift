import XCTest
import SharedCoreKit   // shared Kotlin ed25519, over the same vendored orlp C the Android app compiles

/// GATE: the ed25519 this app signs with must reproduce the canonical cross-platform fixtures
/// exactly. Both apps now call one implementation, so this asserts the packaged XCFramework
/// behaves as expected when consumed from Swift — the Kotlin-side `Ed25519VectorTest` runs the
/// same fixtures but never crosses that boundary. RFC 8032 anchors mean "matches fixture" ==
/// "correct".
final class Ed25519VectorTests: XCTestCase {

    struct Vector: Decodable {
        let name, seed, message, publicKey, signature: String
    }
    struct Fixture: Decodable { let vectors: [Vector] }

    private func loadVectors() throws -> [Vector] {
        let url = Bundle.module.url(forResource: "ed25519", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url, "ed25519.json fixture missing"))
        return try JSONDecoder().decode(Fixture.self, from: data).vectors
    }

    func testEd25519MatchesCanonicalVectors() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        for v in vectors {
            let seed = [UInt8](hex: v.seed)
            let message = [UInt8](hex: v.message)

            let keyPair = SharedEd25519.keyPair(seed: Data(seed))
            let signature = SharedEd25519.sign(message: Data(message), keyPair: keyPair)

            XCTAssertEqual([UInt8](keyPair.publicKey).hexString, v.publicKey,
                           "public key mismatch for \(v.name)")
            XCTAssertEqual([UInt8](signature).hexString, v.signature,
                           "signature mismatch for \(v.name)")

            XCTAssertTrue(
                SharedEd25519.verify(
                    signature: signature,
                    message: Data(message),
                    publicKey: keyPair.publicKey
                ),
                "verify failed for \(v.name)"
            )
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
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
