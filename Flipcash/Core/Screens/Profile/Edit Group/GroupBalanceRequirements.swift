//
//  GroupBalanceRequirements.swift
//  Flipcash
//

import FlipcashCore

extension GroupBalanceRequirements {

    /// The mints the card has to name, without duplicates.
    var mints: Set<PublicKey> {
        Set([join, chat].compactMap { $0?.mints.first })
    }

    /// The one token the requirements name, or nil when they name none, several, or only the
    /// dollar token.
    var soleToken: PublicKey? {
        guard mints.count == 1, let mint = mints.first, mint != .usdf else { return nil }
        return mint
    }

    /// A requirement's amount, worded as the gate panel words it: the dollar amount, plus the
    /// token's name unless it is the dollar token.
    static func formatted(_ requirement: MinimumBalanceRequirement, mintName: String?) -> String {
        let amount = requirement.amount.formattedDroppingZeroFraction()
        let mint = requirement.mints.first
        guard mint != .usdf, let mintName else { return amount }
        return "\(amount) of \(mintName)"
    }
}
