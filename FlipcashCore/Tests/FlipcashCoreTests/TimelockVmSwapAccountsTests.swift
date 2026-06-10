//
//  TimelockVmSwapAccountsTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("TimelockVmSwapAccounts derivation")
struct TimelockVmSwapAccountsTests {

    // MARK: - Fixtures

    private static func testKey(_ seed: Int) -> PublicKey {
        try! PublicKey([UInt8](repeating: UInt8(seed), count: 32))
    }

    private static let owner = testKey(1)
    private static let mint  = testKey(2)

    private static func makeVM(lockDurationInDays: Int) -> VMMetadata {
        VMMetadata(
            vm: testKey(3),
            authority: testKey(4),
            lockDurationInDays: lockDurationInDays
        )
    }

    private static func makeMintMetadata(vmMetadata: VMMetadata?) -> MintMetadata {
        MintMetadata(
            address: mint,
            decimals: 10,
            name: "Test Token",
            symbol: "TEST",
            description: "",
            imageURL: nil,
            vmMetadata: vmMetadata,
            launchpadMetadata: nil
        )
    }

    // MARK: - Tests

    @Test("Init succeeds for a 21-day lock duration")
    func init_21DayLockDuration_succeeds() throws {
        let first = try TimelockVmSwapAccounts(
            with: Self.owner,
            mint: Self.mint,
            vm: Self.makeVM(lockDurationInDays: 21)
        )
        let second = try TimelockVmSwapAccounts(
            with: Self.owner,
            mint: Self.mint,
            vm: Self.makeVM(lockDurationInDays: 21)
        )

        #expect(first == second)
    }

    @Test("Init throws for lock durations that do not fit a byte", arguments: [256, 300])
    func init_oversizedLockDuration_throws(days: Int) {
        #expect(throws: TimelockVmSwapAccounts.Error.invalidLockDuration) {
            try TimelockVmSwapAccounts(
                with: Self.owner,
                mint: Self.mint,
                vm: Self.makeVM(lockDurationInDays: days)
            )
        }
    }

    @Test("timelockSwapAccounts returns nil when vmMetadata is nil")
    func timelockSwapAccounts_missingVMMetadata_returnsNil() {
        let metadata = Self.makeMintMetadata(vmMetadata: nil)

        #expect(metadata.timelockSwapAccounts(owner: Self.owner) == nil)
    }

    @Test("timelockSwapAccounts returns nil for a 300-day lock duration")
    func timelockSwapAccounts_300DayLockDuration_returnsNil() {
        let metadata = Self.makeMintMetadata(vmMetadata: Self.makeVM(lockDurationInDays: 300))

        #expect(metadata.timelockSwapAccounts(owner: Self.owner) == nil)
    }
}
