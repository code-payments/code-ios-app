//
//  MintMetadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-10-07.
//

import Foundation
import FlipcashAPI

public struct MintMetadata: Equatable, Sendable {
    /// Token mint address
    public let address: PublicKey

    /// The number of decimals configured for the mint
    public let decimals: Int

    /// Currency name
    public let name: String

    /// Currency ticker symbol
    public let symbol: String

    /// Currency description
    public let description: String

    /// URL to currency image
    public let imageURL: URL?

    /// Present when a VM exists for the given mint
    public let vmMetadata: VMMetadata?

    /// Present when created by the launchpad via the currency creator program
    public let launchpadMetadata: LaunchpadMetadata?

    public init(
        address: PublicKey,
        decimals: Int,
        name: String,
        symbol: String,
        description: String,
        imageURL: URL?,
        vmMetadata: VMMetadata?,
        launchpadMetadata: LaunchpadMetadata?
    ) {
        self.address = address
        self.decimals = decimals
        self.name = name
        self.symbol = symbol
        self.description = description
        self.imageURL = imageURL
        self.vmMetadata = vmMetadata
        self.launchpadMetadata = launchpadMetadata
    }
}

// MARK: - VMMetadata -

public struct VMMetadata: Equatable, Sendable {
    /// VM address
    public let vm: PublicKey

    /// Authority that subsidizes and authorizes all transactions against the VM
    public let authority: PublicKey

    /// Lock duration of Virtual Timelock Accounts on the VM (hardcoded to 21 days)
    public let lockDurationInDays: Int

    public init(
        vm: PublicKey,
        authority: PublicKey,
        lockDurationInDays: Int
    ) {
        self.vm = vm
        self.authority = authority
        self.lockDurationInDays = lockDurationInDays
    }
}

// MARK: - LaunchpadMetadata -

public struct LaunchpadMetadata: Equatable, Sendable {
    /// The address of the currency config
    public let currencyConfig: PublicKey

    /// The address of the liquidity pool
    public let liquidityPool: PublicKey

    /// The random seed used during currency creation
    public let seed: PublicKey

    /// The address of the authority for the currency
    public let authority: PublicKey

    /// The address where this mint's tokens are locked against the liquidity pool
    public let mintVault: PublicKey

    /// The address where core mint tokens are locked against the liquidity pool
    public let coreMintVault: PublicKey

    /// The address where core mint fees are paid
    public let coreMintFees: PublicKey

    /// Current circulating mint token supply in quarks
    public let supplyFromBonding: UInt64

    /// Current core mint quarks locked in the liquidity pool
    public let coreMintLocked: UInt64

    /// Percent fee for sells in basis points (hardcoded to 1% = 100 bps)
    public let sellFeeBps: Int

    public init(
        currencyConfig: PublicKey,
        liquidityPool: PublicKey,
        seed: PublicKey,
        authority: PublicKey,
        mintVault: PublicKey,
        coreMintVault: PublicKey,
        coreMintFees: PublicKey,
        supplyFromBonding: UInt64,
        coreMintLocked: UInt64,
        sellFeeBps: Int
    ) {
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
    }
}

// MARK: - Errors -

enum MintMetadataError: Swift.Error {
    case failedToParse
}

// MARK: - Proto -

extension MintMetadata {
    init(_ proto: Code_Currency_V1_Mint) throws {
        guard
            let address = PublicKey(proto.address.value)
        else {
            throw MintMetadataError.failedToParse
        }
        
        self.init(
            address: address,
            decimals: Int(proto.decimals),
            name: proto.name,
            symbol: proto.symbol,
            description: proto.description_p,
            imageURL: !proto.imageURL.isEmpty ? URL(string: proto.imageURL) : nil,
            vmMetadata: proto.hasVmMetadata ? try VMMetadata(proto.vmMetadata) : nil,
            launchpadMetadata: proto.hasLaunchpadMetadata ? try LaunchpadMetadata(proto.launchpadMetadata) : nil
        )
    }
}

extension VMMetadata {
    init(_ proto: Code_Currency_V1_VmMetadata) throws {
        guard
            let vm = PublicKey(proto.vm.value),
            let authority = PublicKey(proto.authority.value)
        else {
            throw MintMetadataError.failedToParse
        }
        
        self.init(
            vm: vm,
            authority: authority,
            lockDurationInDays: Int(proto.lockDurationInDays)
        )
    }
}

extension LaunchpadMetadata {
    init(_ proto: Code_Currency_V1_LaunchpadMetadata) throws {
        guard
            let currencyConfig = PublicKey(proto.currencyConfig.value),
            let liquidityPool  = PublicKey(proto.liquidityPool.value),
            let seed           = PublicKey(proto.seed.value),
            let authority      = PublicKey(proto.authority.value),
            let mintVault      = PublicKey(proto.mintVault.value),
            let coreMintVault  = PublicKey(proto.coreMintVault.value),
            let coreMintFees   = PublicKey(proto.coreMintFees.value)
        else {
            throw MintMetadataError.failedToParse
        }
        
        self.init(
            currencyConfig: currencyConfig,
            liquidityPool: liquidityPool,
            seed: seed,
            authority: authority,
            mintVault: mintVault,
            coreMintVault: coreMintVault,
            coreMintFees: coreMintFees,
            supplyFromBonding: proto.supplyFromBonding,
            coreMintLocked: proto.coreMintLocked,
            sellFeeBps: Int(proto.sellFeeBps)
        )
    }
}
