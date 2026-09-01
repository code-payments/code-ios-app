import XCTest
import FlipcashCore

/// GATE: this repo's Solana legacy-message serialization must reproduce the canonical cross-platform
/// vectors exactly. The Android repo asserts the identical vectors — matching guarantees both apps
/// produce byte-identical transaction messages (a divergence = a transaction one platform builds that
/// the chain or the other platform would reject). Reference is the canonical Solana legacy wire format.
final class SolanaMessageVectorTests: XCTestCase {

    struct Account: Decodable { let seed: Int; let role: String }
    struct Instr: Decodable { let programSeed: Int; let accountSeeds: [Int]; let data: String }
    struct Vector: Decodable {
        let name: String
        let accounts: [Account]
        let blockhashSeed: Int
        let instructions: [Instr]
        let expectedMessage: String
    }
    struct Fixture: Decodable { let vectors: [Vector] }

    private func key(_ seed: Int) throws -> PublicKey {
        try PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private func meta(_ seed: Int, _ role: String) throws -> AccountMeta {
        let k = try key(seed)
        switch role {
        case "payer":                       return .payer(publicKey: k)
        case "writable":                    return .writable(publicKey: k)
        case "writable-signer":             return .writable(publicKey: k, signer: true)
        case "readonly", "readonly-program": return .readonly(publicKey: k)
        case "readonly-signer":             return .readonly(publicKey: k, signer: true)
        default: fatalError("unknown role \(role)")
        }
    }

    func testMessageMatchesCanonicalVectors() throws {
        let url = Bundle.module.url(forResource: "solana_message", withExtension: "json", subdirectory: "Fixtures")
        let data = try Data(contentsOf: try XCTUnwrap(url, "solana_message.json fixture missing"))
        let vectors = try JSONDecoder().decode(Fixture.self, from: data).vectors
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        for v in vectors {
            let accounts = try v.accounts.map { try meta($0.seed, $0.role) }
            let blockhash = try Hash([UInt8](repeating: UInt8(v.blockhashSeed), count: 32))
            let instructions = try v.instructions.map { ins in
                Instruction(
                    program: try key(ins.programSeed),
                    // flags irrelevant — compile() only uses the pubkey to resolve indexes
                    accounts: try ins.accountSeeds.map { AccountMeta.readonly(publicKey: try key($0)) },
                    data: Data([UInt8](hex: ins.data))
                )
            }
            let msg = LegacyMessage(accounts: accounts, recentBlockhash: blockhash, instructions: instructions)
            XCTAssertEqual(msg.encode().hexString, v.expectedMessage, "message mismatch for \(v.name)")
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
private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
