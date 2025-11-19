//
//  UserFlags.swift
//  FlipcashCore
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI

public struct UserFlags: Sendable {
    public let isRegistered: Bool
    public let isStaff: Bool
    public let onrampProviders: [OnRampProvider]
    public let preferredOnrampProvider: OnRampProvider
    public let minBuildNumber: Int

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
    public enum OnRampProvider: Int, Sendable {
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

    init(_ proto: Flipcash_Account_V1_UserFlags) {
        self.init(
            isRegistered: proto.isRegisteredAccount,
            isStaff: proto.isStaff,
            onrampProviders: proto.supportedOnRampProviders.map { OnRampProvider($0) },
            preferredOnrampProvider: OnRampProvider(proto.preferredOnRampProvider),
            minBuildNumber: Int(proto.minBuildNumber)
        )
    }
}

extension UserFlags.OnRampProvider {
    init(_ proto: Flipcash_Account_V1_UserFlags.OnRampProvider) {
        switch proto {
        case .unknown:
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
