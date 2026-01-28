//
//  StoredBalance.swift
//  Code
//
//  Created by Dima Bart on 2025-07-04.
//

import Foundation
import FlipcashCore

struct StoredBalance: Identifiable, Sendable, Equatable, Hashable {
    let quarks: UInt64
    let symbol: String
    let name: String
    let supplyFromBonding: UInt64?
    let sellFeeBps: Int?
    let mint: PublicKey
    let vmAuthority: PublicKey?
    let updatedAt: Date
    let imageURL: URL?
    let costBasis: Double?

    let usdf: Quarks

    var id: PublicKey {
        mint
    }
    
    init(quarks: UInt64, symbol: String, name: String, supplyFromBonding: UInt64?, sellFeeBps: Int?, mint: PublicKey, vmAuthority: PublicKey?, updatedAt: Date, imageURL: URL?, costBasis: Double?) throws {
        self.quarks            = quarks
        self.symbol            = symbol
        self.name              = name
        self.supplyFromBonding = supplyFromBonding
        self.sellFeeBps        = sellFeeBps
        self.mint              = mint
        self.vmAuthority       = vmAuthority
        self.updatedAt         = updatedAt
        self.imageURL          = imageURL
        self.costBasis         = costBasis
        
        // For non-USDC currencies that have a bonding
        // curve liquidity provider, we'll compute their
        // equivalent USDC value
        if let supplyFromBonding, let sellFeeBps {
            guard let sellEstimate = Self.bondingCurve.sell(
                tokenQuarks: Int(quarks),
                feeBps: sellFeeBps,
                supplyQuarks: Int(supplyFromBonding)
            ) else {
                throw Error.missingStoredCoreMintForNonReserveToken
            }

            self.usdf = try! Quarks(
                fiatDecimal: sellEstimate.netUSDF.asDecimal(),
                currencyCode: .usd,
                decimals: 6
            )
            
        } else {
            guard symbol == "USDF" else {
                throw Error.missingStoredCoreMintForNonReserveToken
            }
            
            self.usdf = Quarks(
                quarks: quarks,
                currencyCode: .usd,
                decimals: PublicKey.usdf.mintDecimals
            )
        }
    }
    
    func computeExchangedValue(with rate: Rate) -> ExchangedFiat {
        .computeFromQuarks(
            quarks: quarks,
            mint: mint,
            rate: rate,
            supplyQuarks: supplyFromBonding
        )
    }

    /// Computes the appreciation/depreciation of this balance.
    /// Returns a tuple with the ExchangedFiat (absolute value) and whether it's a positive.
    /// Returns nil if cost basis is not available or zero.
    func computeAppreciation(with rate: Rate) -> (value: ExchangedFiat, isPositive: Bool)? {
        guard let costBasis, costBasis > 0 else { return nil }

        let appreciationUSD = usdf.decimalValue - Decimal(costBasis)

        guard let underlying = try? Quarks(
            fiatDecimal: abs(appreciationUSD),
            currencyCode: .usd,
            decimals: PublicKey.usdf.mintDecimals
        ) else { return nil }

        guard let exchangedFiat = try? ExchangedFiat(
            underlying: underlying,
            rate: rate,
            mint: .usdf
        ) else { return nil }

        return (exchangedFiat, appreciationUSD >= 0)
    }
}

extension StoredBalance {
    enum Error: Swift.Error {
        case missingStoredCoreMintForNonReserveToken
    }
}

extension StoredBalance {
    private static let bondingCurve = DiscreteBondingCurve()
}
