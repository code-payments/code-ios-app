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
    
    public init(converted: Fiat, rate: Rate) throws {
        assert(converted.currencyCode == rate.currency, "Rate currency must match Fiat currency")
        
        if converted.currencyCode == .usd {
            self.init(usdc: converted, converted: converted, rate: .oneToOne)
        } else {
            let equivalentUSD = converted.decimalValue / rate.fx
            
            // Trims any quark amount beyond 2 decimal places
            let roundedUSD = equivalentUSD.rounded(to: 2)
            
            let usdc = try Fiat(
                fiatDecimal: roundedUSD,
                currencyCode: .usd
            )
            
            self.init(
                usdc: usdc,
                converted: converted,
                rate: rate
            )
        }
    }
    
    public init(usdc: Fiat, rate: Rate) throws {
        self.init(
            usdc: usdc,
            converted: try Fiat(
                fiatDecimal: usdc.decimalValue * rate.fx,
                currencyCode: rate.currency
            ),
            rate: rate
        )
    }
    
    public init(usdc: Fiat, converted: Fiat) {
        self.init(
            usdc: usdc,
            converted: converted,
            rate: Rate(
                fx: converted.decimalValue / usdc.decimalValue,
                currency: converted.currencyCode
            )
        )
    }
    
    private init(usdc: Fiat, converted: Fiat, rate: Rate) {
        assert(usdc.currencyCode == .usd, "ExchangeFiat usdc must be in USD")
        
        self.usdc = usdc
        self.converted = converted
        self.rate = rate
    }
}

// MARK: - Proto -

extension ExchangedFiat {
    init(_ proto: Code_Transaction_V2_ExchangeData) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        
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
            )
        )
    }
    
    init(_ proto: Flipcash_Common_V1_PaymentAmount) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        
        self.init(
            usdc: Fiat(
                quarks: proto.quarks,
                currencyCode: .usd
            ),
            converted: try Fiat(
                fiatDecimal: Decimal(proto.nativeAmount),
                currencyCode: currency
            )
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
    enum Error: Swift.Error {
        case invalidCurrency
        case invalidNativeAmount
    }
}
