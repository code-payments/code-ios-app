//
//  ExchangedFiat.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation
import FlipcashAPI
import FlipcashCoreAPI
import BigDecimal

/**
 * Represents a monetary value bridge between an on-chain token amount and its localized
 * fiat representation.
 *
 * This maps the relationship between the blockchain reality (USD value for the core mint)
 * and the user's perception (Converted Fiat value or non-USDC token value).
 *
 * @property underlying The raw amount of the core mint token (always denominated in USD for USDC).
 * @property converted The converted value of the specific token in the user's selected currency (e.g., EUR, GBP, CAD).
 * @property rate The exchange rate used to convert between the [underlying] and the [converted].
 * @property mint The Mint address of the token being represented.
 *
 * If the user wants to send, for example, $5 CAD of Jeffy, this will look like:
 *
 * ```
 * underlying: (USD value amount for $5 CAD worth of Jeffy in USDC)
 * converted: (5 CAD in Jeffy)
 * rate: (fx determined by bonding curve for $5 CAD of Jeffy)
 * mint: (Mint address for Jeffy)
 * ```
 */
public struct ExchangedFiat: Equatable, Hashable, Codable, Sendable {
    
    public let underlying: Quarks
    public let converted: Quarks
    public let rate: Rate
    public let mint: PublicKey
    
    public init(converted: Quarks, rate: Rate, mint: PublicKey) throws {
        assert(converted.currencyCode == rate.currency, "Rate currency must match Fiat currency")
        
        let equivalentUSD = converted.decimalValue / rate.fx
        
        let underlying = try Quarks(
            fiatDecimal: equivalentUSD,
            currencyCode: .usd,
            decimals: mint.mintDecimals
        )
        
        self.init(
            underlying: underlying,
            converted: converted,
            rate: rate,
            mint: mint
        )
    }
    
    public init(underlying: Quarks, rate: Rate, mint: PublicKey) throws {
        self.init(
            underlying: underlying,
            converted: try Quarks(
                fiatDecimal: underlying.decimalValue * rate.fx,
                currencyCode: rate.currency,
                decimals: mint.mintDecimals
            ),
            rate: rate,
            mint: mint
        )
    }
    
    public init(underlying: Quarks, converted: Quarks, mint: PublicKey) {
        self.init(
            underlying: underlying,
            converted: converted,
            rate: Rate(
                fx: converted.decimalValue / underlying.decimalValue,
                currency: converted.currencyCode
            ),
            mint: mint
        )
    }
    
    public init(underlying: Quarks, converted: Quarks, rate: Rate, mint: PublicKey) {
        assert(underlying.currencyCode == .usd, "ExchangeFiat usdc must be in USD")
        
        self.underlying = underlying
        self.converted = converted
        self.rate = rate
        self.mint = mint
    }
    
    private static let bondingCurve = DiscreteBondingCurve()
    nonisolated(unsafe) private static let rounding = Rounding(.toNearestOrEven, 36)

    public static func computeFromQuarks(quarks: UInt64, mint: PublicKey, rate: Rate, supplyQuarks: UInt64?) -> ExchangedFiat {
        // `quarks` are expected to be either USDF
        // or custom currency quarks that we'll need
        // to run through the bonding curve to get a
        // valuation

        let exchanged: ExchangedFiat

        if mint != PublicKey.usdf {
            // We can't pass 0 quarks into the sell function
            // because we won't get an accurate rate. In the
            // event that there's a 0 quark balance, we'll
            // pass 1 quark just to get the fx rate.
            let quarksToSell = quarks == 0 ? 1 : quarks

            guard let valuation = bondingCurve.sell(
                tokenQuarks: Int(quarksToSell),
                feeBps: 0,
                supplyQuarks: Int(supplyQuarks!)
            ) else {
                // Fallback to USDC if curve calculation fails
                return try! ExchangedFiat(
                    underlying: Quarks(
                        quarks: quarks,
                        currencyCode: .usd,
                        decimals: mint.mintDecimals
                    ),
                    rate: rate,
                    mint: mint
                )
            }

            let decimalQuarks = BigDecimal(Int(quarksToSell))
            let fiatRate = BigDecimal(rate.fx)
            let fx = valuation.netUSDF
                // Division need to divide by tokens, not quarks
                .divide(decimalQuarks.scaleDown(mint.mintDecimals), Self.rounding)
                // Premultiply the fiat rate (ie. CAD, etc)
                .multiply(fiatRate, Self.rounding)

            exchanged = try! ExchangedFiat(
                underlying: Quarks(
                    quarks: quarks,
                    currencyCode: .usd, // USDF value
                    decimals: mint.mintDecimals
                ),
                rate: .init(
                    fx: fx.asDecimal(),
                    currency: rate.currency
                ),
                mint: mint
            )

        } else {
            exchanged = try! ExchangedFiat(
                underlying: Quarks(
                    quarks: quarks,
                    currencyCode: .usd,
                    decimals: PublicKey.usdf.mintDecimals
                ),
                rate: rate,
                mint: mint
            )
        }

        return exchanged
    }
    
    /// Computes a token valuation from a user-entered fiat amount.
    ///
    /// - Parameters:
    ///   - amount: User-entered fiat amount (in `rate.currency`).
    ///   - rate: Fiat FX rate for the entry currency.
    ///   - mint: Target token mint.
    ///   - supplyQuarks: Current token supply in quarks (10 decimals).
    ///   - balance: Optional USDF-equivalent balance (6 decimals). When provided, the
    ///     entered amount is **silently capped** to this balance. Use this in flows
    ///     like Buy/Sell where FX rounding can cause the entered fiat to slightly
    ///     exceed the displayed balance. Do **not** pass a balance when the flow
    ///     should surface an insufficient-funds error instead of capping.
    ///   - tokenBalanceQuarks: Optional token balance in quarks (mint decimals). Use this
    ///     when the final computed token amount must never exceed the on-chain token
    ///     balance (ex: sell flow where bonding-curve math/rounding can slightly exceed
    ///     the available token balance).
    ///
    /// If both `balance` and `tokenBalanceQuarks` are provided, both caps are enforced:
    /// the fiat amount is capped first, and the resulting token amount is capped second.
    public static func computeFromEntered(
        amount: Foundation.Decimal,
        rate: Rate,
        mint: PublicKey,
        supplyQuarks: UInt64,
        balance: Quarks? = nil,
        tokenBalanceQuarks: UInt64? = nil
    ) -> ExchangedFiat? {
        guard amount > 0 else {
            return nil
        }

        if let balance {
            guard balance.currencyCode == .usd else {
                return nil
            }
            guard balance.decimals == PublicKey.usdf.mintDecimals else {
                return nil
            }
        }

        let cappedAmount: Foundation.Decimal
        if let balance, rate.fx > 0 {
            let usdAmount = amount / rate.fx
            if usdAmount > balance.decimalValue {
                cappedAmount = balance.decimalValue * rate.fx
            } else {
                cappedAmount = amount
            }
        } else {
            cappedAmount = amount
        }

        let valuation: DiscreteBondingCurve.Valuation
        let decimals = mint.mintDecimals

        if mint != PublicKey.usdf {
            guard let computed = bondingCurve.tokensForValueExchange(
                fiat: BigDecimal(cappedAmount),
                fiatRate: BigDecimal(rate.fx),
                supplyQuarks: Int(supplyQuarks)
            ) else {
                return nil
            }
            valuation = computed
        } else {
            valuation = .init(
                tokens: BigDecimal(amount),
                fx: BigDecimal(rate.fx)
            )
        }

        // The rate for the underlying token
        // represented as the 'region' of Rate
        // so in the below example - CAD
        let underlyingRate = Rate(
            fx: valuation.fx.asDecimal(),
            currency: rate.currency
        )

        // This a new fx rate for the token valued in USDC
        // so if the spot price for a token is $0.01 this
        // is an example of CAD -> Tokens:
        // - $5.00 CAD
        // - Rate: 1.40
        // - $3.57 USD
        // - 3.57 / 0.01 = # of tokens

        // For bonded tokens, valuation.tokens is the number of whole tokens.
        // We need to scale it to quarks.
        let tokenQuarks = valuation.tokens.asDecimal().scaleUpInt(decimals)

        if let tokenBalanceQuarks, tokenQuarks > tokenBalanceQuarks {
            return computeFromQuarks(
                quarks: tokenBalanceQuarks,
                mint: mint,
                rate: rate,
                supplyQuarks: supplyQuarks
            )
        }

        let exchanged = ExchangedFiat(
            underlying: Quarks(
                quarks: tokenQuarks,
                currencyCode: .usd,
                decimals: decimals
            ),
            converted: try! Quarks(
                fiatDecimal: cappedAmount,
                currencyCode: rate.currency,
                decimals: decimals
            ),
            rate: underlyingRate,
            mint: mint
        )

        return exchanged
    }
    
    public func subtracting(_ exchangedFiat: ExchangedFiat) throws -> ExchangedFiat {
        guard mint == exchangedFiat.mint else {
            throw Error.mismatchedMint
        }
        
        guard rate.currency == exchangedFiat.rate.currency else {
            throw Error.mismatchedRate
        }
        
        return try ExchangedFiat(
            underlying: try underlying.subtracting(exchangedFiat.underlying),
            rate: rate,
            mint: mint
        )
    }
    
    public func subtracting(fee: Quarks, invert: Bool = false) throws -> ExchangedFiat {
        let feeInQuarks = fee.quarks
        
        guard rate.currency == .usd else {
            throw Error.mismatchedRate
        }
        
        let isValidOperation: () -> Bool = {
            if invert {
                underlying.quarks <= feeInQuarks
            } else {
                feeInQuarks <= underlying.quarks
            }
        }
        
        guard isValidOperation() else {
            throw Error.feeLargerThanAmount
        }
        
        let remainingQuarks = invert ? feeInQuarks - underlying.quarks : underlying.quarks - feeInQuarks
        
        return try ExchangedFiat(
            underlying: Quarks(
                quarks: remainingQuarks,
                currencyCode: .usd,
                decimals: mint.mintDecimals
            ),
            rate: rate,
            mint: mint
        )
    }
    
    public func convert(to rate: Rate) -> ExchangedFiat {
        try! ExchangedFiat(
            underlying: underlying,
            rate: rate,
            mint: mint
        )
    }

    /// Returns true if the converted fiat value would display as non-zero when formatted.
    public func hasDisplayableValue() -> Bool {
        converted.hasDisplayableValue
    }

    /// Returns true when the converted value is non-zero but too small to display
    /// (i.e. it would format as the currency's zero). Use this to decide whether
    /// to prefix the formatted string with "~".
    public func isApproximatelyZero() -> Bool {
        converted.isApproximatelyZero
    }
}

// MARK: - Proto -

extension ExchangedFiat {
    init(_ proto: Ocp_Transaction_V1_ExchangeData) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        let mint     = try PublicKey(proto.mint.value)
        self.init(
            underlying: Quarks(
                quarks: proto.quarks,
                currencyCode: .usd,
                decimals: mint.mintDecimals
            ),
            converted: try Quarks(
                fiatDecimal: Decimal(proto.nativeAmount),
                currencyCode: currency,
                decimals: mint.mintDecimals
            ),
            rate: Rate(
                fx: Decimal(proto.exchangeRate),
                currency: currency
            ),
            mint: mint
        )
    }
    
    init(_ proto: Flipcash_Common_V1_CryptoPaymentAmount) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        let mint     = try PublicKey(proto.mint.value)
        self.init(
            underlying: Quarks(
                quarks: proto.quarks,
                currencyCode: .usd,
                decimals: mint.mintDecimals
            ),
            // Rate is auto-calculated based on converted / underlying
            converted: try Quarks(
                fiatDecimal: Decimal(proto.nativeAmount),
                currencyCode: currency,
                decimals: mint.mintDecimals
            ),
            mint: mint
        )
    }
}

extension ExchangedFiat {
    public var descriptionDictionary: [String: String] {
        [
            "usdc": underlying.formatted(suffix: nil),
            "quarks": "\(underlying.quarks)",
            "fx": rate.fx.formatted(),
            "converted": converted.formatted(suffix: nil),
            "currency": rate.currency.rawValue.uppercased(),
        ]
    }
}

// MARK: - Collection -

extension Collection where Element == ExchangedFiat {
    public func total(rate: Rate) -> ExchangedFiat {
        var totalConverted: Foundation.Decimal = 0
        var totalUnderlying: Foundation.Decimal = 0

        forEach { exchanged in
            totalConverted += exchanged.converted.decimalValue
            totalUnderlying += exchanged.underlying.decimalValue
        }

        return ExchangedFiat(
            underlying: try! Quarks(
                fiatDecimal: totalUnderlying,
                currencyCode: .usd,
                decimals: PublicKey.usdf.mintDecimals
            ),
            converted: try! Quarks(
                fiatDecimal: totalConverted,
                currencyCode: rate.currency,
                decimals: PublicKey.usdf.mintDecimals
            ),
            rate: rate,
            mint: .usdf
        )
    }
}

extension ExchangedFiat {
    public enum Error: Swift.Error {
        case invalidCurrency
        case invalidNativeAmount
        case invalidMint
        case feeLargerThanAmount
        case mismatchedMint
        case mismatchedRate
    }
}
