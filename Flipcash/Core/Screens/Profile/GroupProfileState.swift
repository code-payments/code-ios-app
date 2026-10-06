//
//  GroupProfileState.swift
//  Flipcash
//

import FlipcashCore

/// The one button pinned under a group's profile, decided from the gate and whether the viewer is
/// already in the group.
nonisolated enum GroupProfileCTA: Equatable {
    case none
    case join
    case openChat
    /// Short of the join minimum `amount`, held in `mint` (nil for any holding).
    case buyToJoin(amount: FiatAmount, mint: PublicKey?)
    /// Short of the chat minimum `amount`, held in `mint` (nil for any holding).
    case buyToChat(amount: FiatAmount, mint: PublicKey?)

    /// Reads the verdicts directly rather than ``ConversationGatePresentation``, which ignores
    /// membership: a member who fell under the join minimum is asked to buy back in to chat, not
    /// to join a group they are already in.
    static func resolve(gate: ConversationGate, isMember: Bool) -> GroupProfileCTA {
        if isMember {
            switch gate.speaker {
            case .satisfied:
                return .openChat
            case .unsatisfied(let unmet, _):
                // The speaker verdict carries the unmet listener rules first and its own after, so
                // the last minimum is the chat one when there is one. Buying up to it covers the
                // join minimum as well.
                guard let (amount, mint) = unmet.last(where: \.isMinimumBalance)?.minimumBalance else {
                    // Read-only, staff-only or creator-only: there is nothing to buy, and the
                    // transcript is still the member's to open.
                    return .openChat
                }
                return .buyToChat(amount: amount, mint: mint)
            }
        }

        // A rule in a currency with no rate yet passes the gate provisionally; Join would be a
        // promise the real verdict might take back.
        guard !gate.isProvisional else { return .none }
        switch gate.listener {
        case .satisfied:
            return .join
        case .unsatisfied(_, let primary):
            guard let (amount, mint) = primary.minimumBalance else { return .none }
            return .buyToJoin(amount: amount, mint: mint)
        }
    }
}

nonisolated private extension ConversationGateRequirement {
    var minimumBalance: (FiatAmount, PublicKey?)? {
        switch self {
        case .minimumBalance(let amount, let mint):         return (amount, mint)
        case .staff, .never, .creator, .unsupported:        return nil
        }
    }

    var isMinimumBalance: Bool { minimumBalance != nil }
}

/// The two rows of a group's Balance Requirements card.
nonisolated struct GroupBalanceRequirements: Equatable {
    /// The listener minimum, or nil when joining needs no balance.
    let join: MinimumBalanceRequirement?
    /// The speaker minimum, falling back to ``join`` when the group sets none: speaker rules equal
    /// listener rules when none are set.
    let chat: MinimumBalanceRequirement?

    /// Nil when the group has no minimum balance rule, which hides the card.
    init?(_ rules: ConversationRules?) {
        let join = rules?.listener.lazy.compactMap { rule -> MinimumBalanceRequirement? in
            switch rule {
            case .minimumBalance(let requirement):  return requirement
            case .staff:                            return nil
            }
        }.first
        let speaker = rules?.speaker.lazy.compactMap { rule -> MinimumBalanceRequirement? in
            switch rule {
            case .minimumBalance(let requirement):          return requirement
            case .staff, .never, .creator, .unsupported:    return nil
            }
        }.first
        guard join != nil || speaker != nil else { return nil }
        self.join = join
        self.chat = speaker ?? join
    }
}

/// How much more the user must hold to meet `amount`, stated in its currency and rounded up so
/// buying it is enough. Nil when the requirement is met, or when no rate can restate it.
@MainActor
func balanceShortfall(
    of amount: FiatAmount,
    mint: PublicKey?,
    holdings: some ConversationGateReading,
    rates: [CurrencyCode: Rate]
) -> FiatAmount? {
    guard let required = amount.converted(to: .usd, rates: rates) else { return nil }
    let held = heldBalance(in: mint, session: holdings).roundedToSmallestUnit()
    guard held < required else { return nil }
    let shortfall = required - held
    guard amount.currency != .usd else { return shortfall }
    guard let rate = rates[amount.currency] else { return nil }
    return shortfall.converting(to: rate).ceiledToSmallestUnit()
}
