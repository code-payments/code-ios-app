//
//  BondingCurve.swift
//  Code
//
//  Created by Dima Bart on 2025-10-01.
//

import Foundation
@preconcurrency import BigDecimal

public let r = Rounding(.toNearestOrEven, 70)

/// The continuous exponential bonding curve implementation.
///
/// - Important: This type is deprecated. Use ``DiscreteBondingCurve`` instead,
///   which provides exact, deterministic pricing that matches the Rust implementation.
@available(*, deprecated, message: "Use DiscreteBondingCurve instead for deterministic pricing")
public struct BondingCurve: Sendable {
    
    public static let defaultA = BigDecimal("11400.230149967394933471")
    public static let defaultB = BigDecimal("0.000000877175273521")
    public static let defaultC = BigDecimal("0.000000877175273521")
    
    public static let startPrice = BigDecimal("0.01")
    public static let endPrice   = BigDecimal("1000000")
    public static let maxSupply  = BigDecimal("21000000")
    
    public let a: BigDecimal
    public let b: BigDecimal
    public let c: BigDecimal
    
    public let decimals: Int = 10
    
    // MARK: - Init -
    
    public init(
        a: BigDecimal = BondingCurve.defaultA,
        b: BigDecimal = BondingCurve.defaultB,
        c: BigDecimal = BondingCurve.defaultC
    ) {
        self.a = a
        self.b = b
        self.c = c
    }
    
    // MARK: - Utilities -
    
    private func abOverC() -> BigDecimal {
        a.multiply(b, r).divide(c, r)
    }
    
    private func exp(_ x: BigDecimal) -> BigDecimal {
        BigDecimal.exp(x, r)
    }
    
    private func ln(_ x: BigDecimal) -> BigDecimal {
        BigDecimal.log(x, r)
    }
    
    private func ensureValid(_ x: BigDecimal) throws -> BigDecimal {
        guard !x.isNaN else {
            throw BondingCurveError.internalNaN
        }
        
        return x
    }
}

// MARK: - Buy / Sell (Quarks) -

public extension BondingCurve {
    
    func marketCap(for supply: Int) throws -> Foundation.Decimal {
        let s = BigDecimal(supply).scaleDown(decimals)
        let p = try spotPrice(supply: s)
        return s.multiply(p, r).asDecimal()
    }
    
    func spotPrice(supply: BigDecimal) throws -> BigDecimal {
        let e = exp(c.multiply(supply, r))
        return try ensureValid(a.multiply(b, r).multiply(e, r))
    }
    
    func costToBuy(quarks: Int, supply: Int) -> BigDecimal {
        // ΔS = tokens to buy (in whole tokens), S = current supply (in whole tokens)
        let S  = BigDecimal(supply).scaleDown(decimals)
        let dS = BigDecimal(quarks).scaleDown(decimals)
        let newS = S.add(dS, r)

        // exp(c * S) and exp(c * (S + ΔS))
        let exp_cS   = exp(c.multiply(S, r))
        let exp_cNew = exp(c.multiply(newS, r))

        // cost = (ab/c) * (exp(c*(S+ΔS)) - exp(c*S))
        let diff   = exp_cNew.subtract(exp_cS, r)
        let result = abOverC().multiply(diff, r)
        return try! ensureValid(result)
    }
    
    func valueFromSelling(quarks: Int, tvl: Int) -> BigDecimal {
        // Selling zero returns zero
        if quarks == 0 { return .zero }

        // Convert inputs to curve units:
        // - tokensToSell: from token quarks to whole tokens using this curve's token decimals
        // - valueLocked: from USDC quarks (6) to whole USDC units
        let tokensToSell = BigDecimal(quarks).scaleDown(decimals)
        let valueLocked  = BigDecimal(tvl).scaleDown(6) // USDC has 6 decimals

        print("$L", valueLocked.asString(.plain))
        print("ΔS", tokensToSell.asString(.plain))

        // valueLocked + (ab/c)
        let cvPlusAbOverC = valueLocked.add(abOverC(), r)

        // exp(-c * tokensToSell)
        let cTimesTokens = c.multiply(tokensToSell, r)
        var negCTimesTokens = cTimesTokens
        negCTimesTokens.negate()
        let expTerm = BigDecimal.exp(negCTimesTokens, r)

        // (1 - exp(-c * tokensToSell))
        let oneMinusExp = BigDecimal.one.subtract(expTerm, r)

        // (valueLocked + ab/c) * (1 - exp(-c * ΔS))
        let result = cvPlusAbOverC.multiply(oneMinusExp, r)

        return try! ensureValid(result)
    }
    
    func tokensBought(withUSDC usdcQuarks: Int, tvl: Int) -> BigDecimal {
        guard usdcQuarks > 0 else { return 0 }

        // v: value to spend in USDC units (scale down from quarks with 6 decimals)
        let v = BigDecimal(usdcQuarks).scaleDown(6)

        // valueLocked: current reserve value R(S) in USDC units
        let valueLocked = BigDecimal(tvl).scaleDown(6)

        // ab/c
        let abOverC = abOverC()

        // e^{cS} = R(S)/(ab/c) + 1
        let e_cS = valueLocked.divide(abOverC, r).add(.one, r)

        // ΔS = (1/c) * ln( 1 + v / ((ab/c) * e^{cS}) )
        let denom  = abOverC.multiply(e_cS, r)
        let term   = v.divide(denom, r).add(.one, r)
        let lnTerm = ln(term)
        let delta  = lnTerm.divide(c, r)

        return try! ensureValid(delta)
    }
    
//    v2
//    public func tokensBought(withUSDC usdcQuarks: Int, tvl: Int) -> BigDecimal {
//        guard usdcQuarks > 0 else { return 0 }
//
//        // v: value to spend in USDC units (scale down from quarks with 6 decimals)
//        let v = BigDecimal(usdcQuarks).scaleDown(6)
//
//        // valueLocked: current reserve value R(S) in USDC units (USDC has 6 decimals)
//        let valueLocked = BigDecimal(tvl).scaleDown(6)
//
//        // ab/c
//        let abOverC = abOverC()
//
//        // e^{cS} = R(S)/(ab/c) + 1
//        let e_cS = valueLocked.divide(abOverC, r).add(.one, r)
//
//        // Recover S from TVL: S = (1/c) * ln(e^{cS})
//        let S = ln(e_cS).divide(c, r)
//
//        // tokens = (1/c) * ln( value/(ab/c) + e^{cS} ) - S
//        let term   = v.divide(abOverC, r).add(e_cS, r)
//        let lnTerm = ln(term)
//        let tokens = lnTerm.divide(c, r).subtract(S, r)
//
//        return try! ensureValid(tokens)
//    }
}

// MARK: - Buy / Sell (Decimal) -

extension BondingCurve {
    public struct BuyEstimation {
        public let netTokensToReceive: BigDecimal
        public let fees: BigDecimal
    }
    
    public struct SellEstimation {
        public let netUSDC: BigDecimal
        public let fees: BigDecimal
    }
    
    public struct Valuation {
        public let tokens: BigDecimal
        public let fx: BigDecimal
    }
    
    public func buy(
        usdcQuarks: Int,
        feeBps: Int,
        tvl: Int
    ) -> BuyEstimation {
        let tokensScaled = tokensBought(withUSDC: usdcQuarks, tvl: tvl)
        
        let feePct          = BigDecimal(feeBps).divide(BigDecimal("10000"), r)
        let feeTokensScaled = tokensScaled.multiply(feePct, r)
        let netTokensScaled = tokensScaled.subtract(feeTokensScaled, r)
        
        let netTokensQuarks = netTokensScaled
        let feesQuarks      = feeTokensScaled
        
        return BuyEstimation(
            netTokensToReceive: netTokensQuarks,
            fees: feesQuarks
        )
    }
    
    public func sell(
        quarks: Int,
        feeBps: Int,
        tvl: Int
    ) -> SellEstimation {
        let grossQuarks = valueFromSelling(quarks: quarks, tvl: tvl)
        
        let fee      = BigDecimal(feeBps).divide(BigDecimal("10000"), r)
        let feeValue = grossQuarks.multiply(fee, r)
        let netUSDC  = grossQuarks.subtract(feeValue, r)
        
        return SellEstimation(
            netUSDC: netUSDC,
            fees: feeValue
        )
    }
    
    public func spotTokensFor(fiat: Foundation.Decimal, supply: BigDecimal) throws -> Foundation.Decimal {
        guard fiat > 0 else {
            return 0
        }
        
        let price  = try spotPrice(supply: supply)
        let amount = BigDecimal(fiat)
        let tokens = amount / price
        
        return Decimal(string: tokens.asString())!
    }
    
    public func valueForTokens(
        quarks: Int,
        fx: Foundation.Decimal,
        supplyQuarks: Int
    ) throws -> Valuation {
        guard quarks > 0 else {
            return .init(tokens: 0, fx: 0)
        }

        let tokens = BigDecimal(quarks).scaleDown(decimals)
        let s      = BigDecimal(supplyQuarks).scaleDown(decimals)
        let price  = try spotPrice(supply: s)
        let rate   = BigDecimal(fx)

        // Calculate USDC value (token amount * price)
        let usdc = tokens.multiply(price, r)

        return Valuation(
            tokens: usdc,
            fx: rate.multiply(price, r)
        )
    }
    
    public func tokensForValueExchange(fiat: BigDecimal, fiatRate: BigDecimal, tvl: Int) throws -> Valuation {
        guard fiat.isPositive else {
            return .init(tokens: 0, fx: 0)
        }

        let value = fiat.divide(fiatRate, r)  // USDC value to spend
        let currentValue = BigDecimal(tvl).scaleDown(6)  // Current TVL in USDC units

        guard value.signum > 0 else {
            throw BondingCurveError.nonPositiveValue
        }

        let abOverC = abOverC()
        let newValue = currentValue.subtract(value, r)
        let currentValueOverAbOverC = currentValue.divide(abOverC, r)
        let newValueOverAbOverC = newValue.divide(abOverC, r)

        let lnTerm1 = ln(BigDecimal.one.add(currentValueOverAbOverC, r))
        let lnTerm2 = ln(BigDecimal.one.add(newValueOverAbOverC, r))
        let diffLnTerms = lnTerm1.subtract(lnTerm2, r)

        let tokens = try ensureValid(diffLnTerms.divide(c, r))

        return Valuation(
            tokens: tokens,
            fx: fiat.divide(tokens, r)
        )
    }
}

extension BigDecimal {
    func pow10(_ n: Int) -> BigDecimal {
        BigDecimal.ten.pow(n, r)
    }
    
    func scaleDown(_ d: Int) -> BigDecimal {
        divide(pow10(d), r)
    }
    
    func scaleUp(_ d: Int) -> BigDecimal {
        multiply(pow10(d), r)
    }
}

// MARK: - Print -

private extension String {
    mutating func add(_ string: String, newLine: Bool = true) {
        self = "\(self)\(string)\(newLine ? "\n" : "")"
    }
}

extension BondingCurve {
    func generateChart() -> String {
        var out: String = ""

        out.add("|------|----------------|----------------------------------|----------------------------|")
        out.add("| %    | S              | R(S)                             | R'(S)                      |")
        out.add("|------|----------------|----------------------------------|----------------------------|")

        let step = 210_000
        var supplyInt = 0

        for i in 0...100 {
            // Cost to reach supplyInt from 0
            let cost: BigDecimal = {
                self.costToBuy(
                    quarks: supplyInt * 10_000_000_000,
                    supply: 0
                )
            }()

            // Spot price at supplyInt
            let spotPrice: BigDecimal = {
                try! self.spotPrice(supply: BigDecimal(supplyInt))
            }()

            let percentStr = String(format: "%4d%%", i)
            
            let supply = BigDecimal(supplyInt)
            let supplyStr = supply.asString(.plain)
            let supplyPad = max(0, 15 - supplyStr.count)
            let supplyPadded = String(repeating: " ", count: supplyPad) + supplyStr
            
            let costStr = formatBigDecimalToFixed(cost, decimals: 18)
            let costPad = max(0, 33 - costStr.count)
            let costPadded = String(repeating: " ", count: costPad) + costStr
            
            let spotStr = formatBigDecimalToFixed(spotPrice, decimals: 18)
            let spotPad = max(0, 27 - spotStr.count)
            let spotPadded = String(repeating: " ", count: spotPad) + spotStr

            out.add("|\(percentStr) |\(supplyPadded) |\(costPadded) |\(spotPadded) |")

            supplyInt += step
        }
        
        out.add("|------|----------------|----------------------------------|----------------------------|", newLine: false)
        return out
    }
    
    private func formatBigDecimalToFixed(_ bd: BigDecimal, decimals: Int) -> String {
        let scale = BigDecimal(1, -decimals)
        let rounded = bd.quantize(scale, .toNearestOrEven)
        var s = rounded.asString(.plain)
        if !s.contains(".") {
            s += "."
            s += String(repeating: "0", count: decimals)
        } else {
            if let dotIndex = s.firstIndex(of: ".") {
                let fracCount = s.distance(from: s.index(after: dotIndex), to: s.endIndex)
                let addZeros = decimals - fracCount
                if addZeros > 0 {
                    s += String(repeating: "0", count: addZeros)
                }
            }
        }
        return s
    }
}

// MARK: - Error -

public enum BondingCurveError: Error {
    case nonPositiveValue
    case valueTooLargeForLiquidityCap
    case internalNaN
}
