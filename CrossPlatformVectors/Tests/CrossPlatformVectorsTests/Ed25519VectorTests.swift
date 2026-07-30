import XCTest
import CodeCurves   // vendored ed25519 C (ed25519_create_keypair / ed25519_sign / ed25519_verify)

/// GATE: this repo's ed25519 must reproduce the canonical cross-platform fixtures exactly.
/// The Android repo runs the identical fixtures against its ed25519 — matching outputs on both
/// sides is what guarantees the apps agree. RFC 8032 anchors mean "matches fixture" == "correct".
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

            var pub = [UInt8](repeating: 0, count: 32)
            var priv = [UInt8](repeating: 0, count: 64)
            ed25519_create_keypair(&pub, &priv, seed)

            var sig = [UInt8](repeating: 0, count: 64)
            ed25519_sign(&sig, message, message.count, pub, priv)

            XCTAssertEqual(pub.hexString, v.publicKey, "public key mismatch for \(v.name)")
            XCTAssertEqual(sig.hexString, v.signature, "signature mismatch for \(v.name)")

            let ok = ed25519_verify(sig, message, message.count, pub)
            XCTAssertEqual(ok, 1, "verify failed for \(v.name)")
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
