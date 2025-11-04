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
    let coreMintLocked: UInt64?
    let sellFeeBps: Int?
    let mint: PublicKey
    let vmAuthority: PublicKey?
    let updatedAt: Date
    let imageURL: URL?
    
    let usdcValue: Fiat
    
    var id: PublicKey {
        mint
    }
    
    init(quarks: UInt64, symbol: String, name: String, supplyFromBonding: UInt64?, coreMintLocked: UInt64?, sellFeeBps: Int?, mint: PublicKey, vmAuthority: PublicKey?, updatedAt: Date, imageURL: URL?) throws {
        self.quarks            = quarks
        self.symbol            = symbol
        self.name              = name
        self.supplyFromBonding = supplyFromBonding
        self.coreMintLocked    = coreMintLocked
        self.sellFeeBps        = sellFeeBps
        self.mint              = mint
        self.vmAuthority       = vmAuthority
        self.updatedAt         = updatedAt
        self.imageURL          = imageURL
        
        // For non-USDC currencies that have a bonding
        // curve liquidity provider, we'll compute their
        // equivalent USDC value
        if let coreMintLocked, let sellFeeBps {
            let usdcQuarks = Self.bondingCurve.sell(
                quarks: Int(quarks),
                feeBps: sellFeeBps,
                tvl: Int(coreMintLocked)
            )
            
            self.usdcValue = try! Fiat(
                fiatDecimal: usdcQuarks.netUSDC.asDecimal(),
                currencyCode: .usd,
                decimals: 6
            )
            
        } else {
            guard symbol == "USDC" else {
                throw Error.missingStoredCoreMintForNonUSDCToken
            }
            
            self.usdcValue = Fiat(
                quarks: quarks,
                currencyCode: .usd,
                decimals: PublicKey.usdc.mintDecimals
            )
        }
    }
    
    func computeExchangedValue(with rate: Rate) -> ExchangedFiat {
        .computeFromQuarks(
            quarks: quarks,
            mint: mint,
            rate: rate,
            tvl: coreMintLocked
        )
    }
}

extension StoredBalance {
    enum Error: Swift.Error {
        case missingStoredCoreMintForNonUSDCToken
    }
}

extension StoredBalance {
    private static let bondingCurve = BondingCurve()
}
