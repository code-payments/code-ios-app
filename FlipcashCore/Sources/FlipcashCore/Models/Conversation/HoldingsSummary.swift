//
//  HoldingsSummary.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// What a group's members held of the currency the group is gated on, as of one moment.
public struct HoldingsSummary: Hashable, Sendable {
    public let mint: PublicKey
    /// The total the members held, in the mint's quarks.
    public let quarks: UInt64
    /// How many members held any of the currency.
    public let holderCount: UInt64
    /// When the server computed `quarks` and `holderCount`.
    public let asOf: Date

    public init(mint: PublicKey, quarks: UInt64, holderCount: UInt64, asOf: Date) {
        self.mint = mint
        self.quarks = quarks
        self.holderCount = holderCount
        self.asOf = asOf
    }
}

extension HoldingsSummary {
    /// Builds a summary from its proto, or nil when the mint does not parse.
    init?(_ proto: Flipcash_Chat_V1_HoldingsSummary) {
        guard let mint = try? PublicKey(proto.mint.value) else { return nil }
        self.init(
            mint: mint,
            quarks: proto.quarks,
            holderCount: proto.holderCount,
            asOf: proto.hasAsOf ? proto.asOf.date : .distantPast
        )
    }
}
