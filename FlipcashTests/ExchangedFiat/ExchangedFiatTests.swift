//
//  ExchangedFiatTests.swift
//  Code
//
//  Created by Dima Bart on 2025-11-04.
//

import Foundation
import Testing
@testable import FlipcashCore

struct ExchangedFiatTests {
    
    static let rate = Rate(fx: 1.4, currency: .cad)
    
    static let lhs = try! ExchangedFiat(
        underlying: Quarks(
            quarks: 1_000_000 as UInt64,
            currencyCode: .usd,
            decimals: 10
        ),
        rate: rate,
        mint: .usdc
    )
    
    static let rhs = try! ExchangedFiat(
        underlying: Quarks(
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
        
        #expect(result.underlying.quarks == 500_000)
        #expect(result.rate        == rate)
        #expect(result.mint        == lhs.mint)
    }
    
    @Test
    static func testSubstractionErrors() throws {
        #expect(throws: ExchangedFiat.Error.mismatchedMint) {
            try lhs.subtracting(ExchangedFiat(underlying: 1, rate: rate, mint: .usdcAuthority))
        }
        
        #expect(throws: ExchangedFiat.Error.mismatchedMint) {
            try lhs.subtracting(ExchangedFiat(underlying: 1, rate: Rate(fx: 1.4, currency: .aed), mint: .usdcAuthority))
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
        
        #expect(usd.underlying.quarks               == 55_14_59_074_093) // 55.12 Tokens
        #expect(usd.converted.quarks          ==    59_98_171_930) // 0.59  USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.0108769122")
        
        #expect(cad.underlying.quarks               == 55_14_59_074_093) // 55.12 Tokens
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
        
        #expect(usd.underlying.quarks               == 0) // 55.12 Tokens
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
        
        #expect(usd.underlying.quarks               == 100_500_14_59_074_093) // 100,500.14 Tokens
        #expect(usd.converted.quarks          ==  85_344_16_97_277_396) // $85,344.16 USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.8491944858")
        
        #expect(cad.underlying.quarks               == 100_500_14_59_074_093) // 100,500.14 Tokens
        #expect(cad.converted.quarks          == 119_481_83_76_188_355) // 119.481.83 CAD
        #expect(cad.rate.fx.formatted(to: 10) == "1.1888722801")
    }
    
    @Test
    static func testComputingQuarksFromFiat() throws {
        // Calculate TVL from desired supply using costToBuy
        let curve = BondingCurve()
        let desiredSupply = 100_000 as UInt64  // 100,000 quarks = 0.00001 tokens (10 decimals)
        let tvl = curve.costToBuy(quarks: Int(desiredSupply), supply: 0).scaleUp(6).rounded(.awayFromZero).asDecimal().roundedInt()

        let usd = ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.0, currency: .usd),
            mint: .usdcAuthority,
            tvl: UInt64(tvl)
        )!

        let cad = ExchangedFiat.computeFromEntered(
            amount: 0.59,
            rate: Rate(fx: 1.4, currency: .cad),
            mint: .usdcAuthority,
            tvl: UInt64(tvl)
        )!


        #expect((Decimal(usd.underlying.quarks) / Decimal(cad.underlying.quarks)).formatted(to: 3) == "1.400")

        #expect(usd.underlying.quarks               == 59_00_15_267_762) // 59.00 Tokens
        #expect(usd.converted.quarks          == 5899999999)       // $0.59 USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.0099997412")

        #expect(cad.underlying.quarks               == 42_14_36_360_955) // 42.14 Tokens
        #expect(cad.converted.quarks          == 5899999999)       // $0.59 CAD
        #expect(cad.rate.fx.formatted(to: 10) == "0.0139997412")
    }
    
    // MARK: - Validating Fiat Values -
    
    @Test
    func testAmountsToSend() throws {
        let startTVL =           1_000_000 as UInt64 // USDC quarks (6dp)
        let endTVL   = 100_000_000_000_000 as UInt64

        let fiatToTest: [Decimal] = [
            5.00,
            10.00,
            100.00,
            500.00,
            1_000.00,
        ]

        var output = ""

        var tvl = startTVL
        while tvl <= endTVL {
            for fiat in fiatToTest {
                let exchanged = ExchangedFiat.computeFromEntered(
                    amount: fiat,
                    rate: .oneToOne,
                    mint: .usdcAuthority, // Not USDC
                    tvl: tvl
                )

                let tvlStr     = "\(tvl)".padded(to: 20)
                let underlying = "\(exchanged!.underlying.quarks)".padded(to: 20)
                let converted  = exchanged!.converted.formatted().padded(to: 20)

                output.append("\(tvlStr) \(underlying) \(converted)\n")
            }

            tvl *= 10
        }

        output = output.trimmingCharacters(in: .newlines)

        let expected = """
        1000000              5000658048209        $5.00               
        1000000              10003510574497       $10.00              
        1000000              100432320819833      $100.00             
        1000000              511250352832764      $500.00             
        1000000              1046508918327512     $1,000.00           
        10000000             4996712835333        $5.00               
        10000000             9995616686734        $10.00              
        10000000             100352753544040      $100.00             
        10000000             510837924622184      $500.00             
        10000000             1045644427178340     $1,000.00           
        100000000            4957600405006        $5.00               
        100000000            9917357651988        $10.00              
        100000000            99563960395723       $100.00             
        100000000            506749953488321      $500.00             
        100000000            1037077480269838     $1,000.00           
        1000000000           4597708679971        $5.00               
        1000000000           9197272362330        $10.00              
        1000000000           92308339982136       $100.00             
        1000000000           469202608629476      $500.00             
        1000000000           958548327430506      $1,000.00           
        10000000000          2663887739947        $5.00               
        10000000000          5328398095088        $10.00              
        10000000000          53396384541882       $100.00             
        10000000000          269518606881772      $500.00             
        10000000000          545563645468226      $1,000.00           
        100000000000         511690414900         $5.00               
        100000000000         1023403797656        $10.00              
        100000000000         10238174542457       $100.00             
        100000000000         51283066886112       $500.00             
        100000000000         102797869580410      $1,000.00           
        1000000000000        56358788487          $5.00               
        1000000000000        112717855594         $10.00              
        1000000000000        1127228710628        $100.00             
        1000000000000        5637258461867        $500.00             
        1000000000000        11277305850369       $1,000.00           
        10000000000000       5693625634           $5.00               
        10000000000000       11387254112          $10.00              
        10000000000000       113873052965         $100.00             
        10000000000000       569376639560         $500.00             
        10000000000000       1138781717663        $1,000.00           
        100000000000000      569946547            $5.00               
        100000000000000      1139893122           $10.00              
        100000000000000      11398936344          $100.00             
        100000000000000      56994795699          $500.00             
        100000000000000      113989876342         $1,000.00           
        """
        
        print(output)
        #expect(output == expected)
    }
    
    @Test
    func testQuarksToBalanceConversion() throws {
        let startTVL =           1_000_000 as UInt64 // USDC quarks (6dp)
        let endTVL   = 100_000_000_000_000 as UInt64 // 100,000
        
        let quarks = 1000_000_000_000 as UInt64 // 100 tokens
        
        var output = ""

        var index = 0
        var tvl = startTVL
        while tvl <= endTVL {
            let exchanged = ExchangedFiat.computeFromQuarks(
                quarks: quarks,//quarksToTest[index],
                mint: .usdcAuthority,
                rate: .oneToOne,
                tvl: tvl
            )
            
            let tvlStr     = "\(tvl)".padded(to: 20)
            let underlying = "\(exchanged.underlying.quarks)".padded(to: 20)
            let converted  = exchanged.converted.formatted().padded(to: 20)
            
            tvl *= 10
            index += 1
            
            output.append("\(tvlStr) \(underlying) \(converted)\n")
        }
        
        output = output.trimmingCharacters(in: .newlines)
        
        let expected = """
        1000000              1000000000000        $1.00               
        10000000             1000000000000        $1.00               
        100000000            1000000000000        $1.01               
        1000000000           1000000000000        $1.09               
        10000000000          1000000000000        $1.88               
        100000000000         1000000000000        $9.77               
        1000000000000        1000000000000        $88.71              
        10000000000000       1000000000000        $878.14             
        100000000000000      1000000000000        $8,772.37           
        """
        
        print(output)
        #expect(output == expected)
    }
}

private extension String {
    func padded(to characters: Int) -> String {
        let paddingCount = max(0, characters - self.count)
        return self + String(repeating: " ", count: paddingCount)
    }
}
