//
//  ExchangedFiatTests.swift
//  Code
//
//  Created by Dima Bart on 2025-11-04.
//

import Foundation
import Testing
import FlipcashCore

struct ExchangedFiatTests {
    
    static let rate = Rate(fx: 1.4, currency: .cad)
    
    static let lhs = try! ExchangedFiat(
        usdc: Fiat(
            quarks: 1_000_000 as UInt64,
            currencyCode: .usd,
            decimals: 10
        ),
        rate: rate,
        mint: .usdc
    )
    
    static let rhs = try! ExchangedFiat(
        usdc: Fiat(
            quarks: 500_000 as UInt64,
            currencyCode: .usd,
            decimals: 10
        ),
        rate: rate,
        mint: .usdc
    )
    
    // MARK: - Core -
    
    @Test
    static func testSimpleSubstraction() throws {
        let result = try lhs.subtracting(rhs)
        
        #expect(result.usdc.quarks == 500_000)
        #expect(result.rate        == rate)
        #expect(result.mint        == lhs.mint)
    }
    
    @Test
    static func testSubstractionErrors() throws {
        #expect(throws: ExchangedFiat.Error.mismatchedMint) {
            try lhs.subtracting(ExchangedFiat(usdc: 1, rate: rate, mint: .usdcAuthority))
        }
        
        #expect(throws: ExchangedFiat.Error.mismatchedMint) {
            try lhs.subtracting(ExchangedFiat(usdc: 1, rate: Rate(fx: 1.4, currency: .aed), mint: .usdcAuthority))
        }
    }
    
    // MARK: - Token Valuation -
    
    @Test
    static func testComputingValueFromSmallQuarks() throws {
        let usd = ExchangedFiat.computeFromQuarks(
            quarks: 55_14_59_074_093,
            mint: .usdcAuthority, // We don't want .usdc to simulate other tokens
            rate: Rate(fx: 1.0, currency: .usd),
            tvl: 1_000_000_000
        )
        
        let cad = ExchangedFiat.computeFromQuarks(
            quarks: 55_14_59_074_093,
            mint: .usdcAuthority,
            rate: Rate(fx: 1.4, currency: .cad),
            tvl: 1_000_000_000
        )
        
        #expect(usd.usdc.quarks               == 55_14_59_074_093) // 55.12 Tokens
        #expect(usd.converted.quarks          ==    59_98_171_930) // 0.59  USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.0108769122")
        
        #expect(cad.usdc.quarks               == 55_14_59_074_093) // 55.12 Tokens
        #expect(cad.converted.quarks          ==    83_97_440_702) // 0.83  CAD
        #expect(cad.rate.fx.formatted(to: 10) == "0.0152276771")
    }
    
    @Test
    static func testComputingValueFromZeroQuarks() throws {
        let usd = ExchangedFiat.computeFromQuarks(
            quarks: 0,
            mint: .usdcAuthority, // We don't want .usdc to simulate other tokens
            rate: Rate(fx: 1.0, currency: .usd),
            tvl: 1_000_000_000
        )
        
        #expect(usd.usdc.quarks               == 0) // 55.12 Tokens
        #expect(usd.converted.quarks          == 0) // 0.59  USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.0108771753")
    }
    
    @Test
    static func testComputingValueFromLargeQuarks() throws {
        let usd = ExchangedFiat.computeFromQuarks(
            quarks: 100_500_14_59_074_093,
            mint: .usdcAuthority,
            rate: Rate(fx: 1.0, currency: .usd),
            tvl: 1_000_000_000_000
        )
        
        let cad = ExchangedFiat.computeFromQuarks(
            quarks: 100_500_14_59_074_093,
            mint: .usdcAuthority,
            rate: Rate(fx: 1.4, currency: .cad),
            tvl: 1_000_000_000_000
        )
        
        #expect(usd.usdc.quarks               == 100_500_14_59_074_093) // 100,500.14 Tokens
        #expect(usd.converted.quarks          ==  85_344_16_97_277_396) // $85,344.16 USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.8491944858")
        
        #expect(cad.usdc.quarks               == 100_500_14_59_074_093) // 100,500.14 Tokens
        #expect(cad.converted.quarks          == 119_481_83_76_188_355) // 119.481.83 CAD
        #expect(cad.rate.fx.formatted(to: 10) == "1.1888722801")
    }
    
    @Test
    static func testComputingQuarksFromFiat() throws {
        let usd = ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdcAuthority,
            supplyFromBonding: 100_000
        )!
        
        let cad = ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.4, currency: .cad),
            mint: .usdcAuthority,
            supplyFromBonding: 100_000
        )!
        
        
        #expect((Decimal(usd.usdc.quarks) / Decimal(cad.usdc.quarks)).formatted(to: 3) == "1.400")
        
        #expect(usd.usdc.quarks               == 59_00_15_267_757) // 59.00 Tokens
        #expect(usd.converted.quarks          == 5899999999)       // $0.59 USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.0099997412")
        
        #expect(cad.usdc.quarks               == 42_14_36_360_951) // 42.14 Tokens
        #expect(cad.converted.quarks          == 5899999999)       // $0.59 CAD
        #expect(cad.rate.fx.formatted(to: 10) == "0.0139997412")
    }
}
