//
//  BondingCurve.swift
//  Code
//
//  Created by Dima Bart on 2025-10-01.
//

import Foundation
import BigDecimal

private let r = Rounding(.toNearestOrEven, 100)

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
    
    public var currentSupply: Int
    
    // MARK: - Init -
    
    public init(
        a: BigDecimal = BondingCurve.defaultA,
        b: BigDecimal = BondingCurve.defaultB,
        c: BigDecimal = BondingCurve.defaultC,
        currentSupply: Int = 0
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.currentSupply = currentSupply
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
        guard !x.isNaN else { throw BondingCurveError.internalNaN }
        return x
    }
    
    private var supply: BigDecimal {
        BigDecimal(currentSupply)
    }
}

// MARK: - Buy / Sell -

public extension BondingCurve {
    
    func spotPrice() throws -> BigDecimal {
        let e = exp(c.multiply(supply, r))
        return try ensureValid(a.multiply(b, r).multiply(e, r))
    }
    
    func costToBuy(tokens: Int) -> BigDecimal {
        let newS = BigDecimal(currentSupply + tokens)
        let eNS  = exp(c.multiply(newS, r))
        let eCS  = exp(c.multiply(supply, r))
        let diff = eNS.subtract(eCS, r)
        
        return try! ensureValid(abOverC().multiply(diff, r))
    }
    
    func valueFromSelling(tokens: Int) -> BigDecimal {
        var tNeg = BigDecimal(tokens)
        tNeg.negate()
        
        let eCS      = exp(c.multiply(supply, r))
        let eNeg     = exp(c.multiply(tNeg, r))
        let oneMinus = BigDecimal.one.subtract(eNeg, r)
        let value    = abOverC().multiply(eCS, r).multiply(oneMinus, r)
        return try! ensureValid(value)
    }
    
    func tokensBought(forValue value: BigDecimal) -> BigDecimal {
        guard value.signum > 0 else {
            return 0
        }
        
        let eCS    = exp(c.multiply(supply, r))
        let term   = value.divide(abOverC(), r).add(eCS, r)
        let lnTerm = ln(term)
        let delta  = lnTerm.divide(c, r).subtract(supply, r)
        
        return try! ensureValid(delta)
    }
    
    func tokensForValueExchange(_ value: BigDecimal) throws -> BigDecimal {
        guard value.signum > 0 else {
            throw BondingCurveError.nonPositiveValue
        }
        
        let eCS   = exp(c.multiply(supply, r))
        let denom = abOverC().multiply(eCS, r)
        
        guard value < denom else {
            throw BondingCurveError.valueTooLargeForLiquidityCap
        }
        
        let oneMinus = BigDecimal.one.subtract(value.divide(denom, r), r)
        var lnTerm   = ln(oneMinus)
        lnTerm.negate()
        
        return try! ensureValid(lnTerm.divide(c, r))
    }
    
    @discardableResult
    mutating func buy(tokens: Int) throws -> BigDecimal {
        let cost = costToBuy(tokens: tokens)
        currentSupply += tokens
        return cost
    }
    
    @discardableResult
    mutating func sell(tokens: Int) throws -> BigDecimal {
        let value = valueFromSelling(tokens: tokens)
        currentSupply -= tokens
        return value
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
                var c = self
                c.currentSupply = 0
                return c.costToBuy(tokens: supplyInt)
            }()

            // Spot price at supplyInt
            let spotPrice: BigDecimal = {
                var c = self
                c.currentSupply = supplyInt
                return try! c.spotPrice()
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
