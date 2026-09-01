import XCTest
import FlipcashCore   // Derive.keyPairUsingBIP39 / Derive.Path

/// GATE: this repo's BIP39 + SLIP-0010 (ed25519) key derivation must reproduce the canonical
/// cross-platform fixtures exactly. The Android repo asserts the identical fixtures — matching on
/// both sides guarantees the apps derive the SAME account from a mnemonic (divergence would mean a
/// user's key differs by platform). Anchored to the official BIP39 + SLIP-0010 test vectors.
final class Slip10DerivationVectorTests: XCTestCase {

    struct Vector: Decodable { let name, mnemonic, passphrase, path, publicKey, address: String }
    struct Fixture: Decodable { let vectors: [Vector] }

    func testDerivationMatchesCanonicalVectors() throws {
        let url = Bundle.module.url(forResource: "slip10", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url, "slip10.json fixture missing"))
        let vectors = try JSONDecoder().decode(Fixture.self, from: data).vectors
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        for v in vectors {
            let path = try XCTUnwrap(Derive.Path(v.path), "bad path \(v.path)")
            let phrase = v.mnemonic.split(separator: " ").map(String.init)
            let keyPair = Derive.keyPairUsingBIP39(path: path, phrase: phrase, password: v.passphrase)
            XCTAssertEqual(keyPair.publicKey.bytes.hexString, v.publicKey, "public key mismatch for \(v.name)")
        }
    }
}

private extension Array where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
