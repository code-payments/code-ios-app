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
        
        
        #expect((Decimal(usd.underlying.quarks) / Decimal(cad.underlying.quarks)).formatted(to: 3) == "1.400")
        
        #expect(usd.underlying.quarks               == 59_00_15_267_757) // 59.00 Tokens
        #expect(usd.converted.quarks          == 5899999999)       // $0.59 USD
        #expect(usd.rate.fx.formatted(to: 10) == "0.0099997412")
        
        #expect(cad.underlying.quarks               == 42_14_36_360_951) // 42.14 Tokens
        #expect(cad.converted.quarks          == 5899999999)       // $0.59 CAD
        #expect(cad.rate.fx.formatted(to: 10) == "0.0139997412")
    }
    
    // MARK: - Validating Fiat Values -
    
    @Test
    func testAmountsToSend() throws {
        let startSupply =          1_00_00_000_000 as UInt64 // USDC quarks (6dp)
        let endSupply   = 21_000_000_00_00_000_000 as UInt64 // 100,000
        
        let fiatToTest: [Decimal] = [
            5.00,
            10.00,
            100.00,
            500.00,
            1_000.00,
        ]
        
        var output = ""

        var supply = startSupply
        while supply <= endSupply {
            
            for fiat in fiatToTest {
                let exchanged = ExchangedFiat.computeFromEntered(
                    amount: fiat,
                    rate: .oneToOne,
                    mint: .usdcAuthority, // Not USDC
                    supplyFromBonding: supply
                )
                
                let supplyStr  = "\(supply)".padded(to: 20)
                let underlying = "\(exchanged!.underlying.quarks)".padded(to: 20)
                let converted  = exchanged!.converted.formatted().padded(to: 20)
                
                output.append("\(supplyStr) \(underlying) \(converted)\n")
            }
            
            supply *= 10
        }
        
        output = output.trimmingCharacters(in: .newlines)
        
        let expected = """
        10000000000          5001092401997        $5.00               
        10000000000          10004379663394       $10.00              
        10000000000          100441080923772      $100.00             
        10000000000          511295760602584      $500.00             
        10000000000          1046604099690267     $1,000.00           
        100000000000         5001052911980        $5.00               
        100000000000         10004300648691       $10.00              
        100000000000         100440284483693      $100.00             
        100000000000         511291632270217      $500.00             
        100000000000         1046595446081380     $1,000.00           
        1000000000000        5000658028967        $5.00               
        1000000000000        10003510535997       $10.00              
        1000000000000        100432320431767      $100.00             
        1000000000000        511250350821238      $500.00             
        1000000000000        1046508914111069     $1,000.00           
        10000000000000       4996710913709        $5.00               
        10000000000000       9995612841801        $10.00              
        10000000000000       100352714788750      $100.00             
        10000000000000       510837723741345      $500.00             
        10000000000000       1045644006120180     $1,000.00           
        100000000000000      4957410747532        $5.00               
        100000000000000      9916978171984        $10.00              
        100000000000000      99560135637918       $100.00             
        100000000000000      506730134317242      $500.00             
        100000000000000      1037035954468485     $1,000.00           
        1000000000000000     4581018238122        $5.00               
        1000000000000000     9163878032451        $10.00              
        1000000000000000     91971957711638       $100.00             
        1000000000000000     467464270426932      $500.00             
        1000000000000000     954919469210810      $1,000.00           
        10000000000000000    2079970815228        $5.00               
        10000000000000000    4160321190168        $10.00              
        10000000000000000    41671690967489       $100.00             
        10000000000000000    209898607695880      $500.00             
        10000000000000000    423734428251854      $1,000.00           
        100000000000000000   775257916            $5.00               
        100000000000000000   1550515885           $10.00              
        100000000000000000   15505168342          $100.00             
        100000000000000000   77526052595          $500.00             
        100000000000000000   155052632401         $1,000.00           
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
