//
//  LiquidityPool.swift
//  FlipcashCore
//
//  Created by Claude on 2025-01-26.
//

import Foundation

/// Represents a liquidity pool for token swaps
public struct LiquidityPool: Equatable, Hashable, Codable, Sendable {
    public let address: PublicKey
    public let usdfVault: PublicKey
    public let otherVault: PublicKey

    public init(address: PublicKey, usdfVault: PublicKey, otherVault: PublicKey) {
        self.address = address
        self.usdfVault = usdfVault
        self.otherVault = otherVault
    }
}

extension LiquidityPool {
    /// USDF liquidity pool (USDC ↔ USDF)
    public static let usdf = LiquidityPool(
        address: try! PublicKey(base58: "8q2Kv6wMKDhkg92itiYGxr6jvSHvUhuCay6zrhUncyvK"),
        usdfVault: try! PublicKey(base58: "FmpZMBbtM2vu7vwmRAAQZa7a6jvQntmmoSYCYWXv4EeX"),
        otherVault: try! PublicKey(base58: "3W6Czwv4iWtvv1heeb7MNK97NqW3PmxNvvYW2vipBdsS")
    )
}
