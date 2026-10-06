//
//  GroupBalanceRequirements.swift
//  Flipcash
//

import FlipcashCore

/// The minimum balances a group states for joining and for chatting, as its Balance Requirements
/// card shows them.
struct GroupBalanceRequirements: Equatable {

    /// The listener minimum, or nil when joining asks for no balance.
    let join: MinimumBalanceRequirement?

    /// The speaker minimum, falling back to ``join`` when the group sets none: speaker rules equal
    /// listener rules when none are set.
    let chat: MinimumBalanceRequirement?

    /// Reads the first minimum-balance rule on each side, or returns nil when neither side has one,
    /// so the card is hidden. Staff, creator and never rules state no amount and are skipped.
    init?(rules: ConversationRules?) {
        let join = rules?.listener.lazy.compactMap(Self.minimum).first
        let speaker = rules?.speaker.lazy.compactMap(Self.minimum).first
        guard join != nil || speaker != nil else { return nil }
        self.join = join
        self.chat = speaker ?? join
    }

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

    private static func minimum(_ rule: ConversationListenerRule) -> MinimumBalanceRequirement? {
        switch rule {
        case .minimumBalance(let requirement): requirement
        case .staff:                           nil
        }
    }

    private static func minimum(_ rule: ConversationSpeakerRule) -> MinimumBalanceRequirement? {
        switch rule {
        case .minimumBalance(let requirement):            requirement
        case .staff, .never, .creator, .unsupported:     nil
        }
    }
}
