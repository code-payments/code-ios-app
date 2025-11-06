//
//  BondingCurveTests.swift
//  Code
//
//  Created by Dima Bart on 2025-11-05.
//

//
//  BondingCurveCSVTests.swift
//

import Foundation
import Testing
import BigDecimal
@testable import FlipcashCore
@testable import Flipcash

struct BondingCurveCSVTests {

    @Test
    func estimateCSVTable() throws {
        let curve = BondingCurve()

        let startValue = 10_000          // USDC quarks (6dp)
        let endValue   = 1_000_000_000_000_000

        var output = "value locked,payment value,payment quarks,sell value\n"

        var valueLocked = startValue
        while valueLocked <= endValue {

            // Circulating supply produced by depositing `valueLocked` into an empty pool.
            // Kotlin: Estimator.buy(amountInQuarks=valueLocked, currentSupplyInQuarks=0, feeBps=0)
            let circulatingTokens = curve.tokensBought(
                withUSDC: valueLocked,
                tvl: 0
            )
            
            let valuation = curve.buy(
                usdcQuarks: valueLocked,
                feeBps: 0,
                tvl: 0
            )
            
            #expect(valuation.netTokensToReceive.asString(.plain) == circulatingTokens.asString(.plain))
            
            // Convert tokens -> token quarks (10dp) and HALF_UP round to Int
            let supplyQuarks = circulatingTokens.scaleUp(curve.decimals).asDecimal().roundedInt()

            var paymentValue = startValue
            while paymentValue <= valueLocked {
                let paymentUSDCUnits = BigDecimal(paymentValue).scaleDown(6)

                let valuation = try curve.tokensForValueExchange(
                    fiat: paymentUSDCUnits,
                    fiatRate: 1,
                    supplyQuarks: supplyQuarks
                )

                // tokens -> token quarks (10dp), HALF_UP to Int for the sell() call
                let paymentQuarks = BigDecimal(valuation.tokens).scaleUp(curve.decimals).rounded(.awayFromZero).asDecimal().roundedInt()

                let sellEst = curve.sell(
                    quarks: paymentQuarks,
                    feeBps: 0,
                    tvl: valueLocked
                )
                
                // sell value is BigDecimal in USDC units; convert back to USDC quarks (6dp)
                let sellValueQuarks = sellEst.netUSDC.scaleUp(6).asDecimal().roundedInt()

                output += "\(valueLocked),\(paymentValue),\(paymentQuarks),\(sellValueQuarks)\n"
                
                #expect(Decimal(paymentValue) - Decimal(sellValueQuarks) <= 1.0)

                paymentValue *= 10
            }

            valueLocked *= 10
        }

        let finalOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        print(finalOutput)
        
        #expect(finalOutput == expectedTable)
    }
}

let expectedTable = """
value locked,payment value,payment quarks,sell value
10000,10000,9999995615,10000
100000,10000,9999916670,10000
100000,100000,99999561415,100000
1000000,10000,9999127287,10000
1000000,100000,99991667530,100000
1000000,1000000,999956143801,1000000
10000000,10000,9991240314,10000
10000000,100000,99912797171,100000
10000000,1000000,999167377968,1000000
10000000,10000000,9995616686735,10000000
100000000,10000,9913049529,10000
100000000,100000,99130883181,100000
100000000,1000000,991347623682,1000000
100000000,10000000,9917357651989,10000000
100000000,100000000,99563960395723,100000000
1000000000,10000,9193567062,10000
1000000000,100000,91936004253,100000
1000000000,1000000,919393407620,1000000
1000000000,10000000,9197272362331,10000000
1000000000,100000000,92308339982137,100000000
1000000000,1000000000,958548327430506,1000000000
10000000000,10000,5327154304,10000
10000000000,100000,53271655052,100000
10000000000,1000000,532727752741,1000000
10000000000,10000000,5328398095089,10000000
10000000000,100000000,53396384541882,100000000
10000000000,1000000000,545563645468227,1000000000
10000000000,10000000000,7179501655617262,10000000000
100000000000,10000,1023357910,10000
100000000000,100000,10233583227,100000
100000000000,1000000,102336245651,1000000
100000000000,10000000,1023403797656,10000000
100000000000,100000000,10238174542458,100000000
100000000000,1000000000,102797869580411,1000000000
100000000000,10000000000,1072237618071776,10000000000
100000000000,100000000000,25986777312235155,100000000000
1000000000000,10000,112717299,10000
1000000000000,100000,1127173040,100000
1000000000000,1000000,11271735408,1000000
1000000000000,10000000,112717855595,10000000
1000000000000,100000000,1127228710629,100000000
1000000000000,1000000000,11277305850370,1000000000
1000000000000,10000000000,113278232727384,10000000000
1000000000000,100000000000,1186865247928021,100000000000
1000000000000,1000000000000,51135247513380942,1000000000000
10000000000000,10000,11387249,10000
10000000000000,100000,113872485,100000
10000000000000,1000000,1138724900,1000000
10000000000000,10000000,11387254112,10000000
10000000000000,100000000,113873052965,100000000
10000000000000,1000000000,1138781717664,1000000000
10000000000000,10000000000,11392939355376,10000000000
10000000000000,100000000000,114445014030320,100000000000
10000000000000,1000000000000,1199691804541285,1000000000000
10000000000000,10000000000000,77269006622378866,10000000000000
100000000000000,10000,1139894,10000
100000000000000,100000,11398931,100000
100000000000000,1000000,113989308,1000000
100000000000000,10000000,1139893122,10000000
100000000000000,100000000,11398936345,100000000
100000000000000,1000000000,113989876342,1000000000
100000000000000,10000000000,1139950056520,10000000000
100000000000000,100000000000,11404633262913,100000000000
100000000000000,1000000000000,114563015515597,1000000000000
100000000000000,10000000000000,1200989738763032,10000000000000
100000000000000,100000000000000,103507317078592588,100000000000000
1000000000000000,10000,114002,10000
1000000000000000,100000,1140011,100000
1000000000000000,1000000,11400101,1000000
1000000000000000,10000000,114001003,10000000
1000000000000000,100000000,1140010076,100000000
1000000000000000,1000000000,11400105887,1000000000
1000000000000000,10000000000,114001571865,10000000000
1000000000000000,100000000000,1140067022272,100000000000
1000000000000000,1000000000000,11405803974113,1000000000000
1000000000000000,10000000000000,114574829049150,10000000000000
1000000000000000,100000000000000,1201119686809181,100000000000000
1000000000000000,1000000000000000,129756147464713657,1000000000000000
"""

// MARK: - Helpers

/// HALF_UP rounding to the nearest Int from Decimal
//private func roundToIntHALF_UP(_ d: Foundation.Decimal) -> Int {
//    var src = d
//    var rounded = Decimal()
//    NSDecimalRound(&rounded, &src, 0, .plain) // .plain = round half up (away from zero)
//    return (rounded as NSDecimalNumber).intValue
//}

/*
struct BondingCurveCSVTests {

    @Test
    func estimateCSVTable() throws {
        let curve = BondingCurve()

        let startUSDCLocked = 10_000 // USDC quarks (6dp)
        let endUSDCLocked   = 1_000_000_000_000_000

        var output = "value locked,payment value,payment quarks,sell value\n"

        var usdcLocked = startUSDCLocked
        while usdcLocked <= endUSDCLocked {

            let circulatingTokens = curve.buy(
                usdcQuarks: usdcLocked,
                feeBps: 0,
                tvl: 0
            ).netTokensToReceive
            
            let supplyQuarks = circulatingTokens
                .scaleUp(curve.decimals)
                .roundedToIntHalfUp()

            var paymentValue = startUSDCLocked
            while paymentValue <= usdcLocked {
                do {
                    let valuation = try curve.tokensForValueExchange(
                        fiatDecimal: Decimal(paymentValue).scaleDown(6),
                        fx: 1,
                        supplyQuarks: supplyQuarks
                    )
                    
                    let valuationQuarks = valuation.tokens.scaleUp(curve.decimals).asDecimal().intValue

                    let sellEst = curve.sell(
                        quarks: valuationQuarks,
                        feeBps: 0,
                        tvl: usdcLocked
                    )
                    
                    let netSaleValue = sellEst.netUSDC.scaleUp(6)
                    
                    output += "\(usdcLocked),\(paymentValue),\(valuationQuarks),\(netSaleValue.integer)\n"

                    paymentValue *= 10
                    
                } catch {
                    print(error)
                }
            }

            usdcLocked *= 10
        }

        let finalOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        print(finalOutput)
    }
}

*/

// MARK: - Helpers

extension Foundation.Decimal {
    func roundedInt() -> Int {
        var src     = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &src, 0, .plain) // .plain = round half up (away from zero)
        return (rounded as NSDecimalNumber).intValue
    }
}

extension BigDecimal {
    var integer: Int {
        asDecimal().intValue
    }
    
    func roundedToIntHalfUp() -> Int {
        round(.init(.awayFromZero, 0)).asDecimal().intValue
    }
}

extension Foundation.Decimal {
    var intValue: Int {
        Int(doubleValue)
    }
}
