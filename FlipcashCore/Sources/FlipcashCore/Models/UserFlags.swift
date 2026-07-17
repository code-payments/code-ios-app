//
//  UserFlags.swift
//  FlipcashCore
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

public struct UserFlags: Codable, Sendable {
    public let isRegistered: Bool
    public let isStaff: Bool
    public let onrampProviders: [OnRampProvider]
    public let preferredOnrampProvider: OnRampProvider
    public let minBuildNumber: Int
    public let billExchangeDataTimeout: TimeInterval?
    /// USDF amount that must be purchased when launching a new currency.
    public let newCurrencyPurchaseAmount: TokenAmount
    /// USDF amount that must be paid as a fee when launching a new currency.
    public let newCurrencyFeeAmount: TokenAmount
    /// USDF amount that must be paid as the fee for any withdrawal.
    public let withdrawalFeeAmount: TokenAmount
    /// USDF amount a user must hold to be counted on the Discover leaderboard.
    public let minimumHolderValue: TokenAmount

    /// Whether the send-to-phone-number feature is enabled for this user.
    public let enablePhoneNumberSend: Bool

    /// Whether Coinbase purchase flows require a server-verified email.
    /// When `false`, a locally collected, unverified email is acceptable.
    public let requireCoinbaseEmailVerification: Bool

    /// Which liquidity pool client-built USDC→USDF on-ramp swaps route through.
    public let preferredOnrampUsdcLiquidityPool: UsdcLiquidityPool

    public var hasPreferredOnrampProvider: Bool {
        preferredOnrampProvider != .unknown
    }

    public var hasCoinbase: Bool {
        onrampProviders.contains(.coinbaseVirtual) ||
        onrampProviders.contains(.coinbasePhysicalDebit) ||
        onrampProviders.contains(.coinbasePhysicalCredit)
    }

    public var hasPhantom: Bool {
        onrampProviders.contains(.phantom)
    }

    public var hasOtherCryptoWallets: Bool {
        onrampProviders.contains(.manualDeposit)
    }
}

extension UserFlags {
    public enum OnRampProvider: Int, Codable, Sendable {
        case unknown
        case coinbaseVirtual
        case coinbasePhysicalDebit
        case coinbasePhysicalCredit
        case manualDeposit
        case phantom
        case solflare
        case backpack
        case base
    }

    /// The liquidity pool client-built USDC on-ramp swaps route through;
    /// `unknown` resolves to the legacy Flipcash pool.
    public enum UsdcLiquidityPool: Int, Codable, Sendable {
        case unknown
        case flipcash
        case coinbaseStableSwapper
    }

    init(_ proto: Flipcash_Account_V1_UserFlags) {
        self.init(
            isRegistered: proto.isRegisteredAccount,
            isStaff: proto.isStaff,
            onrampProviders: proto.supportedOnRampProviders.map { OnRampProvider($0) },
            preferredOnrampProvider: OnRampProvider(proto.preferredOnRampProvider),
            minBuildNumber: Int(proto.minBuildNumber),
            billExchangeDataTimeout: proto.hasBillExchangeDataTimeout ? TimeInterval(proto.billExchangeDataTimeout.seconds) : nil,
            newCurrencyPurchaseAmount: TokenAmount(
                quarks: proto.newCurrencyPurchaseAmount,
                mint: .usdf
            ),
            newCurrencyFeeAmount: TokenAmount(
                quarks: proto.newCurrencyFeeAmount,
                mint: .usdf
            ),
            withdrawalFeeAmount: TokenAmount(
                quarks: proto.withdrawalFeeAmount,
                mint: .usdf
            ),
            minimumHolderValue: TokenAmount(
                quarks: proto.minimumHolderValue,
                mint: .usdf
            ),
            enablePhoneNumberSend: proto.enablePhoneNumberSend,
            requireCoinbaseEmailVerification: proto.requireCoinbaseEmailVerification,
            preferredOnrampUsdcLiquidityPool: UsdcLiquidityPool(proto.preferredOnRampUsdcLiquidityPool)
        )
    }
}

extension UserFlags.UsdcLiquidityPool {
    init(_ proto: Flipcash_Account_V1_UserFlags.UsdcLiquidityPool) {
        switch proto {
        case .unknownUsdcLiquidityPool:
            self = .unknown
        case .flipcash:
            self = .flipcash
        case .coinbaseStableSwapper:
            self = .coinbaseStableSwapper
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}

extension UserFlags.OnRampProvider {
    init(_ proto: Flipcash_Account_V1_UserFlags.OnRampProvider) {
        switch proto {
        case .unknownOnRampProvider:
            self = .unknown
        case .coinbaseVirtual:
            self = .coinbaseVirtual
        case .coinbasePhysicalDebit:
            self = .coinbasePhysicalDebit
        case .coinbasePhysicalCredit:
            self = .coinbasePhysicalCredit
        case .manualDeposit:
            self = .manualDeposit
        case .phantom:
            self = .phantom
        case .solflare:
            self = .solflare
        case .backpack:
            self = .backpack
        case .base:
            self = .base
        case .UNRECOGNIZED:
            self = .unknown
        }
    }
}
