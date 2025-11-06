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

public struct ExchangedFiat: Equatable, Hashable, Codable, Sendable {
    
    public let usdc: Fiat
    public let converted: Fiat
    public let rate: Rate
    public let mint: PublicKey
    
    public init(converted: Fiat, rate: Rate, mint: PublicKey) throws {
        assert(converted.currencyCode == rate.currency, "Rate currency must match Fiat currency")
        
        let equivalentUSD = converted.decimalValue / rate.fx
        
        let usdc = try Fiat(
            fiatDecimal: equivalentUSD,
            currencyCode: .usd,
            decimals: mint.mintDecimals
        )
        
        self.init(
            usdc: usdc,
            converted: converted,
            rate: rate,
            mint: mint
        )
    }
    
    public init(usdc: Fiat, rate: Rate, mint: PublicKey) throws {
        self.init(
            usdc: usdc,
            converted: try Fiat(
                fiatDecimal: usdc.decimalValue * rate.fx,
                currencyCode: rate.currency,
                decimals: mint.mintDecimals
            ),
            rate: rate,
            mint: mint
        )
    }
    
    public init(usdc: Fiat, converted: Fiat, mint: PublicKey) {
        self.init(
            usdc: usdc,
            converted: converted,
            rate: Rate(
                fx: converted.decimalValue / usdc.decimalValue,
                currency: converted.currencyCode
            ),
            mint: mint
        )
    }
    
    public init(usdc: Fiat, converted: Fiat, rate: Rate, mint: PublicKey) {
        assert(usdc.currencyCode == .usd, "ExchangeFiat usdc must be in USD")
        
        self.usdc = usdc
        self.converted = converted
        self.rate = rate
        self.mint = mint
    }
    
    public static func computeFromQuarks(quarks: UInt64, mint: PublicKey, rate: Rate, tvl: UInt64?) -> ExchangedFiat {
        
        let exchanged: ExchangedFiat
        
        if mint != PublicKey.usdc {
            
            // We can't pass 0 quarks into the sell function
            // because we won't get an accurate rate. In the
            // event that there's a 0 quark balance, we'll
            // pass 1 quark just to get the fx rate.
            let quarksToSell = quarks == 0 ? 1 : quarks
            
            let curve     = BondingCurve()
            let valuation = curve.sell(
                quarks: Int(quarksToSell),
                feeBps: 0,
                tvl: Int(tvl!)
            )
            
            let decimalQuarks = BigDecimal(Int(quarksToSell))
            let fiatRate = BigDecimal(rate.fx)
            let fx = valuation.netUSDC
                // Division need to divide by tokens, not quarks
                .divide(decimalQuarks.scaleDown(mint.mintDecimals), r)
                // Premultiply the fiat rate (ie. CAD, etc)
                .multiply(fiatRate, r)
            
            exchanged = try! ExchangedFiat(
                usdc: Fiat(
                    quarks: quarks, // USDC value
                    currencyCode: .usd,
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
                usdc: Fiat(
                    quarks: quarks,
                    currencyCode: .usd,
                    decimals: PublicKey.usdc.mintDecimals
                ),
                rate: rate,
                mint: mint
            )
        }
        
        return exchanged
    }
    
    public static func computeFromEntered(amount: Foundation.Decimal, rate: Rate, mint: PublicKey, supplyFromBonding: UInt64) -> ExchangedFiat? {
        guard amount > 0 else {
            return nil
        }
        
        let valuation: BondingCurve.Valuation
        let curve    = BondingCurve()
        let decimals = mint.mintDecimals

        if mint != PublicKey.usdc {
            valuation = try! curve.tokensForValueExchange(
                fiat: BigDecimal(amount),
                fiatRate: BigDecimal(rate.fx),
                supplyQuarks: Int(supplyFromBonding)
            )
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
        
        let exchanged: ExchangedFiat
        if rate.currency == .usd {
            exchanged = ExchangedFiat(
                usdc: try! Fiat(
                    fiatDecimal: valuation.tokens.asDecimal(),
                    currencyCode: underlyingRate.currency,
                    decimals: decimals
                ),
                converted: try! Fiat(
                    fiatDecimal: amount,
                    currencyCode: underlyingRate.currency,
                    decimals: decimals
                ),
                rate: underlyingRate,
                mint: mint
            )
            
        } else {
            exchanged = try! ExchangedFiat(
                converted: .init(
                    fiatDecimal: amount,
                    currencyCode: underlyingRate.currency,
                    decimals: decimals
                ),
                rate: underlyingRate,
                mint: mint
            )
        }
        
        return  exchanged
    }
    
    public func subtracting(_ exchangedFiat: ExchangedFiat) throws -> ExchangedFiat {
        guard mint == exchangedFiat.mint else {
            throw Error.mismatchedMint
        }
        
        guard rate.currency == exchangedFiat.rate.currency else {
            throw Error.mismatchedRate
        }
        
        return try ExchangedFiat(
            usdc: try usdc.subtracting(exchangedFiat.usdc),
            rate: rate,
            mint: mint
        )
    }
    
    public func subtracting(fee: Fiat, invert: Bool = false) throws -> ExchangedFiat {
        let feeInQuarks = fee.quarks
        
        guard rate.currency == .usd else {
            throw Error.mismatchedRate
        }
        
        let isValidOperation: () -> Bool = {
            if invert {
                usdc.quarks <= feeInQuarks
            } else {
                feeInQuarks <= usdc.quarks
            }
        }
        
        guard isValidOperation() else {
            throw Error.feeLargerThanAmount
        }
        
        let remainingQuarks = invert ? feeInQuarks - usdc.quarks : usdc.quarks - feeInQuarks
        
        return try ExchangedFiat(
            usdc: Fiat(
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
            usdc: usdc,
            rate: rate,
            mint: mint
        )
    }
}

// MARK: - Proto -

extension ExchangedFiat {
    init(_ proto: Code_Transaction_V2_ExchangeData) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        let mint     = try PublicKey(proto.mint.value)
        self.init(
            usdc: Fiat(
                quarks: proto.quarks,
                currencyCode: .usd,
                decimals: mint.mintDecimals
            ),
            converted: try Fiat(
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
            usdc: Fiat(
                quarks: proto.quarks,
                currencyCode: .usd,
                decimals: mint.mintDecimals
            ),
            // Rate is auto-calculated based on converted / usdc
            converted: try Fiat(
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
            "usdc": usdc.formatted(suffix: nil),
            "quarks": "\(usdc.quarks)",
            "fx": rate.fx.formatted(),
            "converted": converted.formatted(suffix: nil),
            "currency": rate.currency.rawValue.uppercased(),
        ]
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
