//
//  UnauthenticatedUserFlags.swift
//  FlipcashCore
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI

public struct UnauthenticatedUserFlags: Sendable {
    public let isStaff: Bool
    public let requiresIapForRegistration: Bool
    public let onrampProviders: [UserFlags.OnRampProvider]
    public let preferredOnrampProvider: UserFlags.OnRampProvider
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

extension UnauthenticatedUserFlags {
    init(_ proto: Flipcash_Account_V1_UserFlags) {
        self.init(
            isStaff: proto.isStaff,
            requiresIapForRegistration: proto.requiresIapForRegistration,
            onrampProviders: proto.supportedOnRampProviders.map { UserFlags.OnRampProvider($0) },
            preferredOnrampProvider: UserFlags.OnRampProvider(proto.preferredOnRampProvider),
            minBuildNumber: Int(proto.minBuildNumber)
        )
    }
}
