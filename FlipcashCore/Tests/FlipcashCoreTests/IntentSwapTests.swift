import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("IntentSwap")
struct IntentSwapTests {

    @Test("requestToSubmitSignatures throws when parameters are nil")
    func requestWithoutParameters() throws {
        let intent = try makeIntent()

        #expect(throws: IntentSwap.Error.missingSwapParametersProvided) {
            try intent.requestToSubmitSignatures()
        }
    }

    @Test("requestToSubmitSignatures succeeds with parameters")
    func requestWithParameters() throws {
        let intent = try makeIntent()
        intent.parameters = try makeServerParameters()

        let request = try intent.requestToSubmitSignatures()
        guard case .submitSignatures = request.request else {
            Issue.record("Expected submitSignatures request")
            return
        }
        #expect(!request.submitSignatures.transactionSignatures.isEmpty)
    }

    @Test("sign produces deterministic signatures for same inputs")
    func signIsDeterministic() throws {
        let intent = try makeIntent()
        let params = try makeServerParameters()

        let sigs1 = intent.sign(using: params)
        let sigs2 = intent.sign(using: params)

        #expect(sigs1 == sigs2)
    }
}

// MARK: - Helpers

extension IntentSwapTests {

    private func makeIntent(
        id: SwapId = .generate(),
        owner: KeyPair = .generate()!,
        swapAuthority: KeyPair = .generate()!,
        amount: UInt64 = 1_000_000
    ) throws -> IntentSwap {
        let clientParams = VerifiedSwapMetadata.ClientParameters(
            id: id,
            fromMint: .usdf,
            toMint: PublicKey.generate()!,
            amount: Quarks(quarks: amount, currencyCode: .usd, decimals: 6),
            fundingSource: .submitIntent(id: PublicKey.generate()!)
        )

        let serverParams = VerifiedSwapMetadata.ServerParameters(
            nonce: PublicKey.generate()!,
            blockhash: try Hash(Data(repeating: 1, count: 32))
        )

        let metadata = VerifiedSwapMetadata(
            clientParameters: clientParams,
            serverParameters: serverParams
        )

        return IntentSwap(
            id: id,
            owner: owner,
            metadata: metadata,
            swapAuthority: swapAuthority,
            amount: amount,
            direction: .buy(mint: .makeLaunchpad()),
            waitForBlockchain: false,
            proofSignature: owner.sign(Data(repeating: 0, count: 32))
        )
    }

    private func makeServerParameters() throws -> SwapResponseServerParameters {
        SwapResponseServerParameters(
            kind: .stateful(.init(
                payer: PublicKey.generate()!,
                alts: [],
                computeUnitLimit: 200_000,
                computeUnitPrice: 1000,
                memoValue: "test",
                memoryAccount: PublicKey.generate()!,
                memoryIndex: 0
            ))
        )
    }
}

// MARK: - Test Support

private extension MintMetadata {
    static func makeLaunchpad(
        address: PublicKey = PublicKey.generate()!,
        supplyFromBonding: UInt64 = 50_000 * 10_000_000_000
    ) -> MintMetadata {
        MintMetadata(
            address: address,
            decimals: 10,
            name: "Test Token",
            symbol: "TEST",
            description: "A test token",
            imageURL: nil,
            vmMetadata: VMMetadata(
                vm: .usdc,
                authority: .usdcAuthority,
                lockDurationInDays: 21
            ),
            launchpadMetadata: LaunchpadMetadata(
                currencyConfig: .usdc,
                liquidityPool: .usdc,
                seed: .usdc,
                authority: .usdcAuthority,
                mintVault: .usdc,
                coreMintVault: .usdc,
                coreMintFees: nil,
                supplyFromBonding: supplyFromBonding,
                sellFeeBps: 100
            )
        )
    }
}
