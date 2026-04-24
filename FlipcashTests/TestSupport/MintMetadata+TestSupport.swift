//
//  MintMetadata+TestSupport.swift
//  FlipcashTests
//

import FlipcashCore

extension MintMetadata {
    static func makeLaunchpad(
        address: PublicKey = .jeffy,
        supplyFromBonding: UInt64 = 50_000 * 10_000_000_000
    ) -> MintMetadata {
        MintMetadata(
            address: address,
            decimals: 10,
            name: "Test Token",
            symbol: "TEST",
            description: "A test token",
            imageURL: nil,
            vmMetadata: VMMetadata(
                vm: .usdc,
                authority: .usdcAuthority,
                lockDurationInDays: 21
            ),
            launchpadMetadata: LaunchpadMetadata(
                currencyConfig: .usdc,
                liquidityPool: .usdc,
                seed: .usdc,
                authority: .usdcAuthority,
                mintVault: .usdc,
                coreMintVault: .usdc,
                coreMintFees: nil,
                supplyFromBonding: supplyFromBonding,
                sellFeeBps: 100
            )
        )
    }

    static func makeBasic(
        address: PublicKey = .jeffy,
        socialLinks: [SocialLink] = [],
        billColors: [String] = []
    ) -> MintMetadata {
        MintMetadata(
            address: address,
            decimals: 10,
            name: "Test Token",
            symbol: "TEST",
            description: "A test token",
            imageURL: nil,
            vmMetadata: nil,
            launchpadMetadata: nil,
            socialLinks: socialLinks,
            billColors: billColors
        )
    }
}
