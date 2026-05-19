//
//  TokenAccountInfo+Fixtures.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore
import FlipcashAPI

extension Ocp_Account_V1_TokenAccountInfo {
    /// Mock USDC ATA proto with a configurable balance. Address/mint/owner all
    /// share `PublicKey.mock` — tests that probe the balance don't care about
    /// the keys.
    static func usdcAtaInfo(quarks: UInt64) -> Ocp_Account_V1_TokenAccountInfo {
        let id = PublicKey.mock.solanaAccountID
        var proto = Ocp_Account_V1_TokenAccountInfo()
        proto.address = id
        proto.mint = id
        proto.owner = id
        proto.authority = id
        proto.balance = quarks
        proto.accountType = .associatedTokenAccount
        return proto
    }
}
