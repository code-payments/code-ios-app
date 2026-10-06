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

    /// A requirement's amount, worded as the gate panel words it: the dollar amount, plus the
    /// token's name unless it is the dollar token.
    static func formatted(_ requirement: MinimumBalanceRequirement, mintName: String?) -> String {
        let amount = requirement.amount.formattedDroppingZeroFraction()
        let mint = requirement.mints.first
        guard mint != .usdf, let mintName else { return amount }
        return "\(amount) of \(mintName)"
    }
}
