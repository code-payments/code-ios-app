//
//  ExchangedFiat.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation
import FlipcashAPI
import FlipcashCoreAPI

public struct ExchangedFiat: Equatable, Hashable, Codable, Sendable {
    
    public let usdc: Fiat
    public let converted: Fiat
    public let rate: Rate
    public let mint: PublicKey
    
    public init(converted: Fiat, rate: Rate, mint: PublicKey) throws {
        assert(converted.currencyCode == rate.currency, "Rate currency must match Fiat currency")
        
        if converted.currencyCode == .usd {
            self.init(
                usdc: converted,
                converted: converted,
                rate: .oneToOne,
                mint: mint
            )
        } else {
            let equivalentUSD = converted.decimalValue / rate.fx
            
            // Trims any quark amount beyond 2 decimal places
//            let roundedUSD = equivalentUSD.rounded(to: 2)
            
            let usdc = try Fiat(
                fiatDecimal: equivalentUSD,
                currencyCode: .usd
            )
            
            self.init(
                usdc: usdc,
                converted: converted,
                rate: rate,
                mint: mint
            )
        }
    }
    
    public init(usdc: Fiat, rate: Rate, mint: PublicKey) throws {
        self.init(
            usdc: usdc,
            converted: try Fiat(
                fiatDecimal: usdc.decimalValue * rate.fx,
                currencyCode: rate.currency
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
    
    private init(usdc: Fiat, converted: Fiat, rate: Rate, mint: PublicKey) {
        assert(usdc.currencyCode == .usd, "ExchangeFiat usdc must be in USD")
        
        self.usdc = usdc
        self.converted = converted
        self.rate = rate
        self.mint = mint
    }
    
    public func subtracting(fee: Fiat) throws -> ExchangedFiat {
        assert(fee.currencyCode == .usd, "Fee must be in USD")
        
        let feeInQuarks = fee.quarks
        
        guard feeInQuarks < usdc.quarks else {
            throw Error.feeLargerThanAmount
        }
        
        let remainingQuarks = usdc.quarks - feeInQuarks
        
        return try ExchangedFiat(
            usdc: Fiat(
                quarks: remainingQuarks,
                currencyCode: .usd
            ),
            rate: rate,
            mint: mint
        )
    }
}

// MARK: - Proto -

extension ExchangedFiat {
    init(_ proto: Code_Transaction_V2_ExchangeData) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        
        guard let mint = PublicKey(proto.mint.value) else {
            throw Error.invalidMint
        }
        
        self.init(
            usdc: Fiat(
                quarks: proto.quarks,
                currencyCode: .usd
            ),
            converted: try Fiat(
                fiatDecimal: Decimal(proto.nativeAmount),
                currencyCode: currency
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
        
        guard let mint = PublicKey(proto.mint.value) else {
            throw Error.invalidMint
        }
        
        self.init(
            usdc: Fiat(
                quarks: proto.quarks,
                currencyCode: .usd
            ),
            converted: try Fiat(
                fiatDecimal: Decimal(proto.nativeAmount),
                currencyCode: currency
            ),
            mint: mint
            // Rate is auto-calculated based on converted / usdc
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
    }
}
