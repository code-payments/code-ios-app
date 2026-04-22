//
//  TokenAmount.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-20.
//

import Foundation

/// On-chain token amount. Mirrors the proto `(mint, quarks)` pair in
/// `Ocp_Transaction_V1_ExchangeData` and `Flipcash_Common_V1_CryptoPaymentAmount`.
///
/// No currency code — the mint is the identity. Decimals come from the mint.
/// Cannot represent a fiat value; that is what `FiatAmount` is for.
public struct TokenAmount: Equatable, Hashable, Codable, Sendable {

    public let quarks: UInt64
    public let mint: PublicKey

    public var decimalValue: Decimal { quarks.scaleDown(mint.mintDecimals) }
    public var decimals: Int         { mint.mintDecimals }

    public init(quarks: UInt64, mint: PublicKey) {
        self.quarks = quarks
        self.mint = mint
    }

    public init(wholeTokens: Decimal, mint: PublicKey) {
        self.init(
            quarks: wholeTokens.scaleUpInt(mint.mintDecimals),
            mint: mint,
        )
    }

    public static func zero(mint: PublicKey) -> TokenAmount {
        TokenAmount(quarks: 0, mint: mint)
    }
}

// MARK: - Arithmetic -

extension TokenAmount {
    public static func - (lhs: TokenAmount, rhs: TokenAmount) -> TokenAmount {
        precondition(lhs.mint == rhs.mint, "Cannot subtract TokenAmounts with different mints")
        precondition(lhs.quarks >= rhs.quarks, "TokenAmount subtraction underflow — check sufficient funds before subtracting")
        return TokenAmount(quarks: lhs.quarks - rhs.quarks, mint: lhs.mint)
    }

    public static func + (lhs: TokenAmount, rhs: TokenAmount) -> TokenAmount {
        precondition(lhs.mint == rhs.mint, "Cannot add TokenAmounts with different mints")
        let (sum, overflow) = lhs.quarks.addingReportingOverflow(rhs.quarks)
        precondition(!overflow, "TokenAmount addition overflow")
        return TokenAmount(quarks: sum, mint: lhs.mint)
    }
}

// MARK: - Comparable -

extension TokenAmount: Comparable {
    public static func < (lhs: TokenAmount, rhs: TokenAmount) -> Bool {
        precondition(lhs.mint == rhs.mint, "Cannot compare TokenAmounts with different mints")
        return lhs.quarks < rhs.quarks
    }
}

// MARK: - Description -

extension TokenAmount: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "TokenAmount(quarks: \(quarks), mint: \(mint.base58))"
    }

    public var debugDescription: String { description }
}
