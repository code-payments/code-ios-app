import Foundation
import Testing
import CryptoKit
import FlipcashAPI
@testable import FlipcashCore

/// `test-vectors/multi_payment_intent.json`: `IntentMultiTransfer` must emit one no-privacy
/// transfer per payment, in order, and each action must sign the same compact message the
/// Android builder signs. The canonical copy lives in the orchestrator repo; this one is synced.
/// Never edit it locally.
///
/// The intent is built through the production type. The fixture's source vault is 32 copies of a
/// seed byte, which no timelock derivation produces, so the cluster is the real one for
/// `signerSeed` with its vault replaced through its `Codable` form.
@Suite struct MultiPaymentIntentVectorTests {

    struct VerifiedStateFixture: Decodable, Sendable {
        let currency: String
        let rate: String
    }

    /// `destinationOwnerSeed` is an integer, or the string "sourceAuthority".
    enum OwnerSeed: Decodable, Sendable {
        case seed(Int)
        case sourceAuthority

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let seed = try? c.decode(Int.self) { self = .seed(seed) } else {
                let name = try c.decode(String.self)
                guard name == "sourceAuthority" else {
                    throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown owner \(name)")
                }
                self = .sourceAuthority
            }
        }
    }

    struct Payment: Decodable, Sendable {
        let destinationSeed: Int
        let destinationOwnerSeed: OwnerSeed
        let quarks: String
        let mintSeed: Int
        let currency: String
        let nativeAmount: String
    }

    struct Action: Decodable, Sendable {
        let id: Int
        let sourceSeed: Int
        let authority: String
        let destinationSeed: Int
        let mintSeed: Int
        let amount: String
        let nonceSeed: Int
        let nonceValueSeed: Int
        let message: String
        let sha256: String
        let signature: String
    }

    struct ExpectedMetadata: Decodable, Sendable {
        struct Payment: Decodable, Sendable {
            let destinationSeed: Int
            let destinationOwnerSeed: Int
            let quarks: String
            let nativeAmount: String
            let currency: String
        }
        let sourceSeed: Int
        let mintSeed: Int
        let payments: [Payment]
    }

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let sourceVaultSeed: Int
        let sourceAuthority: String
        let signerSeed: String
        let mintSeed: Int
        let verifiedState: VerifiedStateFixture
        let payments: [Payment]
        let expectedActions: [Action]
        let expectedMetadata: ExpectedMetadata
        var testDescription: String { name }
    }

    struct Rejection: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let sourceVaultSeed: Int
        let sourceAuthority: String
        let signerSeed: String
        let mintSeed: Int
        let verifiedState: VerifiedStateFixture
        let payments: [Payment]
        let expectedError: String
        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let vectors: [Vector]
        let rejections: [Rejection]
    }

    static let vectors: [Vector] = (try? loadFixture().vectors) ?? []
    static let rejections: [Rejection] = (try? loadFixture().rejections) ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "multi_payment_intent", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        let fixture = try Self.loadFixture()
        #expect(!fixture.vectors.isEmpty && !fixture.rejections.isEmpty)
    }

    @Test(arguments: vectors)
    func intentMatchesCanonicalVector(_ v: Vector) throws {
        let (source, intent) = try Self.makeIntent(
            signerSeed: v.signerSeed, sourceAuthority: v.sourceAuthority, sourceVaultSeed: v.sourceVaultSeed,
            mintSeed: v.mintSeed, verifiedState: v.verifiedState, payments: v.payments
        )

        // The server returns one nonce and blockhash per action.
        try intent.apply(parameters: v.expectedActions.map {
            ServerParameter(
                actionID: $0.id,
                parameter: nil,
                configs: [.init(nonce: try Self.key($0.nonceSeed), blockhash: try Self.key($0.nonceValueSeed))]
            )
        })

        // Actions: count, then id, source, authority, mint, destination and amount in order.
        let actions = intent.actions.map { $0.action() }
        #expect(actions.count == v.expectedActions.count)
        for (action, expected) in zip(actions, v.expectedActions) {
            let transfer = action.noPrivacyTransfer
            #expect(Int(action.id) == expected.id)
            #expect(transfer.source == (try Self.key(expected.sourceSeed)).solanaAccountID)
            #expect(transfer.source == source.vaultPublicKey.solanaAccountID)
            #expect(transfer.authority.value.hexString == expected.authority)
            #expect(transfer.mint == (try Self.key(expected.mintSeed)).solanaAccountID)
            #expect(transfer.destination == (try Self.key(expected.destinationSeed)).solanaAccountID)
            #expect(String(transfer.amount) == expected.amount)
        }

        // Signing: message bytes, hash and signature per action.
        let signatures = try intent.signatures()
        #expect(signatures.count == v.expectedActions.count)
        for (index, expected) in v.expectedActions.enumerated() {
            let messages = try intent.actions[index].compactMessages()
            #expect(messages.count == 1)
            let message = try #require(messages.first).data
            #expect(message.hexString == expected.message, "message bytes mismatch for action \(expected.id)")
            #expect(Data(CryptoKit.SHA256.hash(data: message)).hexString == expected.sha256, "sha256 mismatch for action \(expected.id)")
            #expect(signatures[index].data.hexString == expected.signature, "signature mismatch for action \(expected.id)")
        }

        // Metadata.
        let expectedMetadata = v.expectedMetadata
        let metadata = intent.metadata().sendPublicMultiPayment
        #expect(metadata.source == (try Self.key(expectedMetadata.sourceSeed)).solanaAccountID)
        #expect(metadata.mint == (try Self.key(expectedMetadata.mintSeed)).solanaAccountID)
        #expect(metadata.payments.count == expectedMetadata.payments.count)
        for (proto, expected) in zip(metadata.payments, expectedMetadata.payments) {
            #expect(proto.destination == (try Self.key(expected.destinationSeed)).solanaAccountID)
            #expect(proto.hasDestinationOwner)
            #expect(proto.destinationOwner == (try Self.key(expected.destinationOwnerSeed)).solanaAccountID)
            #expect(String(proto.clientExchangeData.quarks) == expected.quarks)
            // `native_amount` is a double on the wire; `Decimal.doubleValue` divides by ten per
            // digit, so it can land an ulp or so from the correctly rounded value.
            let native = try #require(Double(expected.nativeAmount))
            #expect(abs(proto.clientExchangeData.nativeAmount - native) <= native * 1e-12,
                    "native \(proto.clientExchangeData.nativeAmount) vs \(expected.nativeAmount)")
            #expect(proto.clientExchangeData.coreMintFiatExchangeRate.exchangeRate.currencyCode == expected.currency)
        }
    }

    @Test(arguments: rejections)
    func builderRejectsInvalidIntent(_ r: Rejection) throws {
        let thrown = #expect(throws: IntentMultiTransfer.Error.self) {
            try Self.makeIntent(
                signerSeed: r.signerSeed, sourceAuthority: r.sourceAuthority, sourceVaultSeed: r.sourceVaultSeed,
                mintSeed: r.mintSeed, verifiedState: r.verifiedState, payments: r.payments
            )
        }
        let rule: String? = switch thrown {
        case .invalidPaymentCount: "count"
        case .mintMismatch: "mintMismatch"
        case .duplicateDestination: "duplicateDestination"
        case .duplicateDestinationOwner: "duplicateDestinationOwner"
        case .destinationIsSource: "destinationIsSource"
        case .currencyMismatch: "currencyMismatch"
        case nil: nil
        }
        #expect(rule == r.expectedError)
    }

    // MARK: - Helpers

    private static func makeIntent(
        signerSeed: String,
        sourceAuthority: String,
        sourceVaultSeed: Int,
        mintSeed: Int,
        verifiedState: VerifiedStateFixture,
        payments fixturePayments: [Payment]
    ) throws -> (AccountCluster, IntentMultiTransfer) {
        let signer = KeyPair(seed: try Seed32(Self.bytes(hex: signerSeed)))
        #expect(signer.publicKey.data.hexString == sourceAuthority)

        let source = try Self.cluster(signer: signer, mint: try Self.key(mintSeed), vault: try Self.key(sourceVaultSeed))
        #expect(source.authorityPublicKey.data.hexString == sourceAuthority)

        let payments = try fixturePayments.map { p -> IntentMultiTransfer.Payment in
            let currency = try CurrencyCode(currencyCode: p.currency)
            let owner: PublicKey = switch p.destinationOwnerSeed {
            case .seed(let seed): try Self.key(seed)
            case .sourceAuthority: source.authorityPublicKey
            }
            return IntentMultiTransfer.Payment(
                destination: try Self.key(p.destinationSeed),
                destinationOwner: owner,
                exchangedFiat: ExchangedFiat(
                    onChainAmount: TokenAmount(quarks: try #require(UInt64(p.quarks)), mint: try Self.key(p.mintSeed)),
                    nativeAmount: FiatAmount(value: try #require(Decimal(string: p.nativeAmount)), currency: currency),
                    currencyRate: Rate(fx: 1, currency: currency)
                )
            )
        }

        var rate = Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate()
        rate.exchangeRate.currencyCode = verifiedState.currency
        rate.exchangeRate.exchangeRate = try #require(Double(verifiedState.rate))
        let intent = try IntentMultiTransfer(
            rendezvous: .generate()!,
            sourceCluster: source,
            payments: payments,
            verifiedState: VerifiedState(rateProto: rate)
        )
        return (source, intent)
    }

    private static func key(_ seed: Int) throws -> PublicKey {
        try PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static func bytes(hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    /// The real cluster for `signer`, with its timelock vault swapped for `vault`.
    private static func cluster(signer: KeyPair, mint: PublicKey, vault: PublicKey) throws -> AccountCluster {
        let derived = AccountCluster(
            authority: DerivedKey(path: .primary(), keyPair: signer),
            mint: mint,
            timeAuthority: .usdcAuthority
        )
        let encoder = JSONEncoder()
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(derived)) as? [String: Any])
        var timelock = try #require(json["timelock"] as? [String: Any])
        var vaultJSON = try #require(timelock["vault"] as? [String: Any])
        let wrapped = try #require(JSONSerialization.jsonObject(with: encoder.encode([vault])) as? [Any])
        vaultJSON["publicKey"] = try #require(wrapped.first)
        timelock["vault"] = vaultJSON
        json["timelock"] = timelock
        return try JSONDecoder().decode(AccountCluster.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
