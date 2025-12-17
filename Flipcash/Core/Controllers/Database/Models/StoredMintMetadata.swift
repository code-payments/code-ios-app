//
//  StoredMintMetadata.swift
//  Code
//
//  Created by Dima Bart on 2025-07-04.
//

import Foundation
import FlipcashCore

struct StoredMintMetadata: Identifiable, Sendable, Equatable, Hashable {
    
    let mint: PublicKey
    let name: String
    let symbol: String
    let decimals: Int
    let bio: String?
    let imageURL: URL?
    let vmAddress: PublicKey?
    let vmAuthority: PublicKey?
    let lockDuration: Int?
    let currencyConfig: PublicKey?
    let liquidityPool: PublicKey?
    let seed: PublicKey?
    let authority: PublicKey?
    let mintVault: PublicKey?
    let coreMintVault: PublicKey?
    let coreMintFees: PublicKey?
    let supplyFromBonding: UInt64?
    let coreMintLocked: UInt64?
    let sellFeeBps: Int?
    
    let updatedAt: Date
    
    var id: PublicKey {
        mint
    }
    
    init(mint: PublicKey, name: String, symbol: String, decimals: Int, bio: String?, imageURL: URL?, vmAddress: PublicKey?, vmAuthority: PublicKey?, lockDuration: Int?, currencyConfig: PublicKey?, liquidityPool: PublicKey?, seed: PublicKey?, authority: PublicKey?, mintVault: PublicKey?, coreMintVault: PublicKey?, coreMintFees: PublicKey?, supplyFromBonding: UInt64?, coreMintLocked: UInt64?, sellFeeBps: Int?, updatedAt: Date) {
        self.mint = mint
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.bio = bio
        self.imageURL = imageURL
        self.vmAddress = vmAddress
        self.vmAuthority = vmAuthority
        self.lockDuration = lockDuration
        self.currencyConfig = currencyConfig
        self.liquidityPool = liquidityPool
        self.seed = seed
        self.authority = authority
        self.mintVault = mintVault
        self.coreMintVault = coreMintVault
        self.coreMintFees = coreMintFees
        self.supplyFromBonding = supplyFromBonding
        self.coreMintLocked = coreMintLocked
        self.sellFeeBps = sellFeeBps
        self.updatedAt = updatedAt
    }
}

extension StoredMintMetadata {
    /// Converts StoredMintMetadata to MintMetadata
    var metadata: MintMetadata {
        let vmMetadata: VMMetadata? = {
            guard let vmAddress = vmAddress,
                  let vmAuthority = vmAuthority,
                  let lockDuration = lockDuration else {
                return nil
            }
            return VMMetadata(
                vm: vmAddress,
                authority: vmAuthority,
                lockDurationInDays: lockDuration
            )
        }()
        
        let launchpadMetadata: LaunchpadMetadata? = {
            guard let currencyConfig = currencyConfig,
                  let liquidityPool = liquidityPool,
                  let seed = seed,
                  let authority = authority,
                  let mintVault = mintVault,
                  let coreMintVault = coreMintVault,
                  let coreMintFees = coreMintFees,
                  let supplyFromBonding = supplyFromBonding,
                  let coreMintLocked = coreMintLocked,
                  let sellFeeBps = sellFeeBps else {
                return nil
            }
            return LaunchpadMetadata(
                currencyConfig: currencyConfig,
                liquidityPool: liquidityPool,
                seed: seed,
                authority: authority,
                mintVault: mintVault,
                coreMintVault: coreMintVault,
                coreMintFees: coreMintFees,
                supplyFromBonding: supplyFromBonding,
                coreMintLocked: coreMintLocked,
                sellFeeBps: sellFeeBps
            )
        }()
        
        return MintMetadata(
            address: mint,
            decimals: decimals,
            name: name,
            symbol: symbol,
            description: bio ?? "",
            imageURL: imageURL,
            vmMetadata: vmMetadata,
            launchpadMetadata: launchpadMetadata
        )
    }
}

//extension StoredMintMetadata {
//    enum Error: Swift.Error {
//        
//    }
//}
