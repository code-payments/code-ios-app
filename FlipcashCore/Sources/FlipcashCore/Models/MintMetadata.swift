//
//  MintMetadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-10-07.
//

import Foundation
import FlipcashAPI

// MARK: - SocialLink -

public enum SocialLink: Equatable, Sendable, Codable, Identifiable {
    case website(URL)
    case x(String)
    case telegram(String)
    case discord(String)
    
    public var id: String {
        switch self {
        case .website(let url):
            return "website:\(url.absoluteString)"
        case .x(let value):
            return "x:\(value)"
        case .telegram(let value):
            return "telegram:\(value)"
        case .discord(let value):
            return "discord:\(value)"
        }
    }
}

// MARK: - MintMetadata -

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

    /// Social links for this currency
    public let socialLinks: [SocialLink]

    /// Bill customization colors as hex strings (e.g. "#19191A")
    public let billColors: [String]

    /// Timestamp the currency was created
    public let createdAt: Date?

    /// Holder metrics (only populated by the Discover RPC)
    public let holderMetrics: HolderMetrics?

    public init(
        address: PublicKey,
        decimals: Int,
        name: String,
        symbol: String,
        description: String,
        imageURL: URL?,
        vmMetadata: VMMetadata?,
        launchpadMetadata: LaunchpadMetadata?,
        socialLinks: [SocialLink] = [],
        billColors: [String] = [],
        createdAt: Date? = nil,
        holderMetrics: HolderMetrics? = nil
    ) {
        self.address = address
        self.decimals = decimals
        self.name = name
        self.symbol = symbol
        self.description = description
        self.imageURL = imageURL
        self.vmMetadata = vmMetadata
        self.launchpadMetadata = launchpadMetadata
        self.socialLinks = socialLinks
        self.billColors = billColors
        self.createdAt = createdAt
        self.holderMetrics = holderMetrics
    }

    /// A bare-bones `MintMetadata` for a freshly-launched currency mint. Used
    /// when the swap pipeline requires a `MintMetadata` for the `SwapDirection`
    /// API but the launch-buy code path doesn't actually consume any of the
    /// metadata fields (it derives every account from the server's
    /// `ReserveNewCurrencyServerParameter`).
    public static func launchStub(address: PublicKey) -> MintMetadata {
        MintMetadata(
            address: address,
            decimals: 10, // Reserve TOKEN_DECIMALS
            name: "",
            symbol: "",
            description: "",
            imageURL: nil,
            vmMetadata: nil,
            launchpadMetadata: nil
        )
    }

    public static let usdf: MintMetadata =
        .init(
            address: PublicKey.usdf,
            decimals: 6,
            name: "USDF",
            symbol: "USDF",
            description: "",
            imageURL: URL(string: "https://raw.githubusercontent.com/p2p-org/solana-token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png"),
            vmMetadata: .init(
                vm: PublicKey.deriveVMAccount(
                    mint: PublicKey.usdf,
                    timeAuthority: .usdcAuthority,
                    lockout: TimelockDerivedAccounts.lockoutInDays
                )!.publicKey,
                authority: .usdcAuthority,
                lockDurationInDays: Int(TimelockDerivedAccounts.lockoutInDays)),
            launchpadMetadata: nil
        )
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

extension VMMetadata {
    public var omnibus: PublicKey {
        return PublicKey.deriveVmOmnibusAddress(vm: vm)!.publicKey
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
    public let coreMintFees: PublicKey?

    /// Current circulating mint token supply in quarks
    public let supplyFromBonding: UInt64

    /// Percent fee for sells in basis points (hardcoded to 1% = 100 bps)
    public let sellFeeBps: Int

    /// The current price in USD
    public let price: Double

    /// The current market capitalization in USD
    public let marketCap: Double

    public init(
        currencyConfig: PublicKey,
        liquidityPool: PublicKey,
        seed: PublicKey,
        authority: PublicKey,
        mintVault: PublicKey,
        coreMintVault: PublicKey,
        coreMintFees: PublicKey?,
        supplyFromBonding: UInt64,
        sellFeeBps: Int,
        price: Double = 0,
        marketCap: Double = 0
    ) {
        self.currencyConfig = currencyConfig
        self.liquidityPool = liquidityPool
        self.seed = seed
        self.authority = authority
        self.mintVault = mintVault
        self.coreMintVault = coreMintVault
        self.coreMintFees = coreMintFees
        self.supplyFromBonding = supplyFromBonding
        self.sellFeeBps = sellFeeBps
        self.price = price
        self.marketCap = marketCap
    }
}

// MARK: - HolderMetrics -

public struct HolderMetrics: Equatable, Sendable {
    /// Current number of holders
    public let currentHolders: UInt64

    /// Net holder changes for various time ranges
    public let holderDeltas: [HolderDelta]

    public struct HolderDelta: Equatable, Sendable {
        public let range: Ocp_Currency_V1_PredefinedRange
        public let delta: Int64

        public init(range: Ocp_Currency_V1_PredefinedRange, delta: Int64) {
            self.range = range
            self.delta = delta
        }
    }

    public init(currentHolders: UInt64, holderDeltas: [HolderDelta]) {
        self.currentHolders = currentHolders
        self.holderDeltas = holderDeltas
    }
}

// MARK: - Errors -

enum MintMetadataError: Swift.Error {
    case failedToParse
}

// MARK: - Proto -

extension MintMetadata {
    init(_ proto: Ocp_Currency_V1_Mint) throws {
        let socialLinks: [SocialLink] = proto.socialLinks.compactMap { link in
            switch link.type {
            case .website(let website):
                guard let url = URL(string: website.url) else { return nil }
                return .website(url)
            case .x(let x):
                guard !x.username.isEmpty else { return nil }
                return .x(x.username)
            case .telegram(let telegram):
                guard !telegram.username.isEmpty else { return nil }
                return .telegram(telegram.username)
            case .discord(let discord):
                guard !discord.inviteCode.isEmpty else { return nil }
                return .discord(discord.inviteCode)
            case nil:
                return nil
            }
        }

        let billColors: [String] = {
            guard proto.hasBillCustomization else { return [] }
            return proto.billCustomization.colors.map(\.hex)
        }()

        self.init(
            address: try PublicKey(proto.address.value),
            decimals: Int(proto.decimals),
            name: proto.name,
            symbol: proto.symbol,
            description: proto.description_p,
            imageURL: !proto.imageURL.isEmpty ? URL(string: proto.imageURL) : nil,
            vmMetadata: proto.hasVmMetadata ? try VMMetadata(proto.vmMetadata) : nil,
            launchpadMetadata: proto.hasLaunchpadMetadata ? try LaunchpadMetadata(proto.launchpadMetadata) : nil,
            socialLinks: socialLinks,
            billColors: billColors,
            createdAt: proto.hasCreatedAt ? proto.createdAt.date : nil,
            holderMetrics: proto.hasHolderMetrics ? HolderMetrics(proto.holderMetrics) : nil
        )
    }
    
    public func timelockSwapAccounts(owner: PublicKey) -> TimelockVmSwapAccounts? {
        guard let vm = vmMetadata else { return nil }
        
        let timelockAccounts: TimelockVmSwapAccounts
        do {
            timelockAccounts = try TimelockVmSwapAccounts(
                with: owner,
                mint: address,
                vm: vm
            )
        } catch {
            return nil
        }
        
        return timelockAccounts
    }
}

extension VMMetadata {
    init(_ proto: Ocp_Currency_V1_VmMetadata) throws {
        self.init(
            vm: try PublicKey(proto.vm.value),
            authority: try PublicKey(proto.authority.value),
            lockDurationInDays: Int(proto.lockDurationInDays)
        )
    }
}

extension LaunchpadMetadata {
    init(_ proto: Ocp_Currency_V1_LaunchpadMetadata) throws {
        self.init(
            currencyConfig: try PublicKey(proto.currencyConfig.value),
            liquidityPool: try PublicKey(proto.liquidityPool.value),
            seed: try PublicKey(proto.seed.value),
            authority: try PublicKey(proto.authority.value),
            mintVault: try PublicKey(proto.mintVault.value),
            coreMintVault: try PublicKey(proto.coreMintVault.value),
            coreMintFees: nil,
            supplyFromBonding: proto.supplyFromBonding,
            sellFeeBps: Int(proto.sellFeeBps),
            price: proto.price,
            marketCap: proto.marketCap
        )
    }
}

extension HolderMetrics {
    init(_ proto: Ocp_Currency_V1_HolderMetrics) {
        self.init(
            currentHolders: proto.currentHolders,
            holderDeltas: proto.holderDeltas.map {
                HolderDelta(range: $0.range, delta: $0.delta)
            }
        )
    }
}
