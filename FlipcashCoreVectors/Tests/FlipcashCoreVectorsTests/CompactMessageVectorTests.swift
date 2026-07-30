import XCTest
import FlipcashCore
import CryptoKit

/// GATE: this repo's intent-signing "compact message" (the bytes signed per action) must match the
/// canonical cross-platform vectors. The Android repo asserts the identical vectors — matching
/// guarantees both apps sign the SAME payload for a transfer/withdraw (a divergence = one platform
/// producing a signature the server rejects). The message LAYOUT (field order, "transfer" domain,
/// little-endian amount) is verified identical by source inspection on both sides; this test gates the
/// byte composition (pubkey serialization + LE amount) and SHA-256. The signature is ed25519 over the
/// hash — already gated by ed25519.json.
final class CompactMessageVectorTests: XCTestCase {

    struct Vector: Decodable {
        let name, domain, message, sha256: String
        let sourceSeed, destinationSeed, nonceSeed, nonceValueSeed: Int
        let amount: String?
    }
    struct Fixture: Decodable { let vectors: [Vector] }

    private func key(_ seed: Int) throws -> PublicKey { try PublicKey([UInt8](repeating: UInt8(seed), count: 32)) }

    func testCompactMessageMatchesCanonicalVectors() throws {
        let url = Bundle.module.url(forResource: "compact_message", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url, "compact_message.json fixture missing"))
        let vectors = try JSONDecoder().decode(Fixture.self, from: data).vectors
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        for v in vectors {
            var msg = Data(v.domain.utf8)
            msg.append(try key(v.sourceSeed).data)
            msg.append(try key(v.destinationSeed).data)
            if let a = v.amount, let amount = UInt64(a) {
                withUnsafeBytes(of: amount.littleEndian) { msg.append(contentsOf: $0) }
            }
            msg.append(try key(v.nonceSeed).data)
            msg.append(try key(v.nonceValueSeed).data)

            XCTAssertEqual(msg.hexString, v.message, "message bytes mismatch for \(v.name)")
            let digest = Data(CryptoKit.SHA256.hash(data: msg))
            XCTAssertEqual(digest.hexString, v.sha256, "sha256 mismatch for \(v.name)")
        }
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
