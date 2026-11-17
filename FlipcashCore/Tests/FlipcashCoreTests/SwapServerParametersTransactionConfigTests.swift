//
//  SwapServerParametersTransactionConfigTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("Swap server parameters carry the v1 transaction fields")
struct SwapServerParametersTransactionConfigTests {

    private static func key(_ seed: UInt8) -> PublicKey {
        try! PublicKey([UInt8](repeating: seed, count: 32))
    }

    private static let blockhash: Ocp_Common_V1_Blockhash = .with { $0.value = Data(repeating: 99, count: 32) }

    private static let configProto: Ocp_Common_V1_SolanaTransactionConfig = .with {
        $0.computeUnitLimit = 1_400_000
        $0.loadedAccountsDataSizeLimit = 65_536
        $0.priorityFeeLamports = 5_000
        $0.heapSize = 262_144
    }

    private static let expectedConfig = SolanaTransactionConfig(
        computeUnitLimit: 1_400_000,
        loadedAccountsDataSizeLimit: 65_536,
        priorityFeeLamports: 5_000,
        heapSize: 262_144
    )

    private static func newCurrencyProto() -> Ocp_Transaction_V1_StatefulSwapResponse.ServerParameters.ReserveNewCurrencyServerParameter {
        var proto = Ocp_Transaction_V1_StatefulSwapResponse.ServerParameters.ReserveNewCurrencyServerParameter()
        proto.payer = key(1).solanaAccountID
        proto.nonce = key(2).solanaAccountID
        proto.blockhash = blockhash
        proto.authority = key(4).solanaAccountID
        proto.seed = key(5).solanaAccountID
        proto.feeDestination = key(6).solanaAccountID
        return proto
    }

    private static func memoryAccountProto(
        _ seed: UInt8,
        name: String
    ) -> Ocp_Transaction_V1_StatefulSwapResponse.ServerParameters.ReserveNewCurrencyServerParameter.VmMemoryAccountInitialization {
        .with {
            $0.address = key(seed).solanaAccountID
            $0.name = name
            $0.numAccounts = 32_000
            $0.accountSize = 74
            $0.resizeSizes = [10_240, 20_480]
            $0.rentTopUpLamports = 1_000_000
        }
    }

    @Test("A v0 new-currency response leaves the v1 fields empty")
    func newCurrency_v0_leavesV1FieldsEmpty() throws {
        let parsed = try #require(SwapResponseServerParameters.ReserveNewCurrency(Self.newCurrencyProto()))

        #expect(parsed.transactionConfig == nil)
        #expect(parsed.memoryAccounts.isEmpty)
        #expect(parsed.feeAccountOwner == nil)
    }

    @Test("A v1 new-currency response carries the config, memory accounts in order, and fee account owner")
    func newCurrency_v1_carriesV1Fields() throws {
        var proto = Self.newCurrencyProto()
        proto.transactionConfig = Self.configProto
        proto.memoryAccounts = [Self.memoryAccountProto(10, name: "first"), Self.memoryAccountProto(11, name: "second")]
        proto.feeAccountOwner = Self.key(12).solanaAccountID

        let parsed = try #require(SwapResponseServerParameters.ReserveNewCurrency(proto))

        #expect(parsed.transactionConfig == Self.expectedConfig)
        #expect(parsed.feeAccountOwner == Self.key(12))
        #expect(parsed.memoryAccounts == [
            .init(address: Self.key(10), name: "first", numAccounts: 32_000, accountSize: 74, resizeSizes: [10_240, 20_480], rentTopUpLamports: 1_000_000),
            .init(address: Self.key(11), name: "second", numAccounts: 32_000, accountSize: 74, resizeSizes: [10_240, 20_480], rentTopUpLamports: 1_000_000),
        ])
    }

    @Test("A malformed memory account address or fee account owner fails the parse")
    func newCurrency_malformedV1Field_returnsNil() {
        var badMemory = Self.newCurrencyProto()
        var memory = Self.memoryAccountProto(10, name: "first")
        memory.address = .with { $0.value = Data([1, 2, 3]) }
        badMemory.memoryAccounts = [memory]
        #expect(SwapResponseServerParameters.ReserveNewCurrency(badMemory) == nil)

        var badOwner = Self.newCurrencyProto()
        badOwner.feeAccountOwner = .with { $0.value = Data([1, 2, 3]) }
        #expect(SwapResponseServerParameters.ReserveNewCurrency(badOwner) == nil)
    }

    @Test("The existing-currency, stateful stablecoin and stateless params carry the config only when set")
    func otherParams_carryConfigWhenSet() throws {
        var existing = Ocp_Transaction_V1_StatefulSwapResponse.ServerParameters.ReserveExistingCurrencyServerParameters()
        existing.payer = Self.key(1).solanaAccountID
        existing.memoryAccount = Self.key(7).solanaAccountID
        #expect(try #require(SwapResponseServerParameters.CurrencyCreatorStateful(existing)).transactionConfig == nil)
        existing.transactionConfig = Self.configProto
        #expect(try #require(SwapResponseServerParameters.CurrencyCreatorStateful(existing)).transactionConfig == Self.expectedConfig)

        var stateful = Ocp_Transaction_V1_StatefulSwapResponse.ServerParameters.CoinbaseStableSwapperServerParameter()
        stateful.payer = Self.key(1).solanaAccountID
        stateful.nonce = Self.key(2).solanaAccountID
        stateful.blockhash = Self.blockhash
        stateful.feeDestination = Self.key(6).solanaAccountID
        stateful.poolFeeRecipient = Self.key(8).solanaAccountID
        #expect(try #require(SwapResponseServerParameters.CoinbaseStableSwapServerParameters(stateful)).transactionConfig == nil)
        stateful.transactionConfig = Self.configProto
        #expect(try #require(SwapResponseServerParameters.CoinbaseStableSwapServerParameters(stateful)).transactionConfig == Self.expectedConfig)

        var stateless = Ocp_Transaction_V1_StatelessSwapResponse.ServerParameters.CoinbaseStableSwapperServerParameter()
        stateless.payer = Self.key(1).solanaAccountID
        stateless.blockhash = Self.blockhash
        stateless.poolFeeRecipient = Self.key(8).solanaAccountID
        #expect(try #require(StatelessSwapServerParameters(stateless)).transactionConfig == nil)
        stateless.transactionConfig = Self.configProto
        #expect(try #require(StatelessSwapServerParameters(stateless)).transactionConfig == Self.expectedConfig)
    }
}
