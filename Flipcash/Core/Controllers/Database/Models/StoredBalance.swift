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
    let costBasis: Double

    let usdf: Quarks

    var id: PublicKey {
        mint
    }
    
    init(quarks: UInt64, symbol: String, name: String, supplyFromBonding: UInt64?, sellFeeBps: Int?, mint: PublicKey, vmAuthority: PublicKey?, updatedAt: Date, imageURL: URL?, costBasis: Double) throws {
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
        if let supplyFromBonding {
            guard let sellEstimate = Self.bondingCurve.sell(
                tokenQuarks: Int(quarks),
                feeBps: 0,
                supplyQuarks: Int(supplyFromBonding)
            ) else {
                throw Error.missingStoredCoreMintForNonReserveToken
            }

            // Floor so the stored USDF stays ≤ the curve's
            // exact BigDecimal TVL.
            self.usdf = try! Quarks(
                fiatDecimal: sellEstimate.netUSDF.asDecimal().roundedDown(to: PublicKey.usdf.mintDecimals),
                currencyCode: .usd,
                decimals: PublicKey.usdf.mintDecimals
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
        .compute(
            onChainAmount: TokenAmount(quarks: quarks, mint: mint),
            rate: rate,
            supplyQuarks: supplyFromBonding
        )
    }

    /// Computes the appreciation/depreciation of this balance.
    /// Returns a tuple with the ExchangedFiat (absolute value) and whether it's positive.
    func computeAppreciation(with rate: Rate) -> (value: ExchangedFiat, isPositive: Bool) {
        let appreciationUSD = usdf.decimalValue - Decimal(costBasis)
        let usdAbs = FiatAmount.usd(abs(appreciationUSD))

        let onChain = TokenAmount(wholeTokens: usdAbs.value, mint: .usdf)

        let exchangedFiat = ExchangedFiat(
            onChainAmount: onChain,
            nativeAmount: usdAbs.converting(to: rate),
            currencyRate: rate,
        )

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
