//
//  StoredMintMetadata.swift
//  Code
//
//  Created by Dima Bart on 2025-07-04.
//

import Foundation
import FlipcashCore

nonisolated struct StoredMintMetadata: Identifiable, Sendable, Equatable, Hashable {
    
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
    let sellFeeBps: Int?

    let socialLinks: String?
    let billColors: String?

    let createdAt: Date?

    let updatedAt: Date

    var id: PublicKey {
        mint
    }

    init(mint: PublicKey, name: String, symbol: String, decimals: Int, bio: String?, imageURL: URL?, vmAddress: PublicKey?, vmAuthority: PublicKey?, lockDuration: Int?, currencyConfig: PublicKey?, liquidityPool: PublicKey?, seed: PublicKey?, authority: PublicKey?, mintVault: PublicKey?, coreMintVault: PublicKey?, coreMintFees: PublicKey?, supplyFromBonding: UInt64?, sellFeeBps: Int?, socialLinks: String? = nil, billColors: String? = nil, createdAt: Date? = nil, updatedAt: Date) {
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
        self.sellFeeBps = sellFeeBps
        self.socialLinks = socialLinks
        self.billColors = billColors
        self.createdAt = createdAt
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
                  let supplyFromBonding = supplyFromBonding,
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
                coreMintFees: nil,
                supplyFromBonding: supplyFromBonding,
                sellFeeBps: sellFeeBps
            )
        }()
        
        let decodedSocialLinks: [SocialLink] = {
            guard let json = socialLinks, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([SocialLink].self, from: data)) ?? []
        }()

        let decodedBillColors: [String] = {
            guard let json = billColors, let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }()

        return MintMetadata(
            address: mint,
            decimals: decimals,
            name: name,
            symbol: symbol,
            description: bio ?? "",
            imageURL: imageURL,
            vmMetadata: vmMetadata,
            launchpadMetadata: launchpadMetadata,
            socialLinks: decodedSocialLinks,
            billColors: decodedBillColors
        )
    }
}

extension StoredMintMetadata {
    /// Creates a StoredMintMetadata from a MintMetadata for immediate display.
    /// Used when navigating from screens that already have the full metadata
    /// (e.g. Currency Discovery) to avoid a loading flash.
    init(_ metadata: MintMetadata) {
        let encodedSocialLinks: String? = {
            guard !metadata.socialLinks.isEmpty,
                  let data = try? JSONEncoder().encode(metadata.socialLinks) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        let encodedBillColors: String? = {
            guard !metadata.billColors.isEmpty,
                  let data = try? JSONEncoder().encode(metadata.billColors) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        self.init(
            mint: metadata.address,
            name: metadata.name,
            symbol: metadata.symbol,
            decimals: metadata.decimals,
            bio: metadata.description,
            imageURL: metadata.imageURL,
            vmAddress: metadata.vmMetadata?.vm,
            vmAuthority: metadata.vmMetadata?.authority,
            lockDuration: metadata.vmMetadata?.lockDurationInDays,
            currencyConfig: metadata.launchpadMetadata?.currencyConfig,
            liquidityPool: metadata.launchpadMetadata?.liquidityPool,
            seed: metadata.launchpadMetadata?.seed,
            authority: metadata.launchpadMetadata?.authority,
            mintVault: metadata.launchpadMetadata?.mintVault,
            coreMintVault: metadata.launchpadMetadata?.coreMintVault,
            coreMintFees: metadata.launchpadMetadata?.coreMintFees,
            supplyFromBonding: metadata.launchpadMetadata?.supplyFromBonding,
            sellFeeBps: metadata.launchpadMetadata?.sellFeeBps,
            socialLinks: encodedSocialLinks,
            billColors: encodedBillColors,
            createdAt: metadata.createdAt,
            updatedAt: .now
        )
    }
}
