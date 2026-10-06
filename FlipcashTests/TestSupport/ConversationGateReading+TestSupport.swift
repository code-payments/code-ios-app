//
//  ConversationGateReading+TestSupport.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash
import FlipcashCore
import FlipcashStore

/// Stands in for `Session`, which the gate reads three things from.
final class StubGateHoldings: ConversationGateReading {
    var isStaff: Bool
    var userID: UserID
    var totalBalance: ExchangedFiat
    private var balances: [PublicKey: StoredBalance]

    init(isStaff: Bool = false, userID: UserID = UUID(), totalUSD: Decimal = 0, balances: [PublicKey: StoredBalance] = [:]) {
        self.isStaff = isStaff
        self.userID = userID
        self.totalBalance = ExchangedFiat(
            nativeAmount: .usd(totalUSD),
            rate: Rate(fx: 1, currency: .usd)
        )
        self.balances = balances
    }

    func balance(for mint: PublicKey) -> StoredBalance? {
        balances[mint]
    }
}

extension StoredBalance {

    /// A USDF holding worth `usd`, which is the one mint whose stored USD value
    /// needs no bonding curve.
    static func usdfHolding(usd: Decimal) throws -> StoredBalance {
        try StoredBalance(
            quarks: NSDecimalNumber(decimal: usd * 1_000_000).uint64Value,
            symbol: "USDF",
            name: "USDF Coin",
            supplyFromBonding: nil,
            sellFeeBps: nil,
            mint: .usdf,
            vmAuthority: nil,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )
    }
}
