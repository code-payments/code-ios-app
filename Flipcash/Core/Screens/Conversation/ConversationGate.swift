//
//  ConversationGate.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashStore

/// What the conversation gate weighs: staff standing, the USD worth of one
/// holding, and the USD worth of everything held.
@MainActor
protocol ConversationGateReading: AnyObject {
    var isStaff: Bool { get }
    var totalBalance: ExchangedFiat { get }
    func balance(for mint: PublicKey) -> StoredBalance?
}

extension Session: ConversationGateReading {
    var isStaff: Bool { userFlags?.isStaff == true }
}

/// A requirement the user does not meet, and everything needed to name it.
enum ConversationGateRequirement: Equatable {
    /// Hold at least `amount` in `mint`, or across every mint when `mint` is nil.
    case minimumBalance(amount: FiatAmount, mint: PublicKey?)
    /// Flipcash staff only. There is no action a user can take, so no CTA.
    case staff
}

/// Whether one class of rules is met, and if not, which of them aren't.
enum ConversationGateVerdict: Equatable {
    case satisfied
    /// Every unmet rule in the order the server listed them, plus the one to
    /// name — the first unmet minimum balance, since it is the only requirement
    /// a user can act on, falling back to the first unmet rule.
    case unsatisfied(unmet: [ConversationGateRequirement], primary: ConversationGateRequirement)

    var isSatisfied: Bool {
        switch self {
        case .satisfied:   return true
        case .unsatisfied: return false
        }
    }

    /// The requirement to put in front of the user, or nil when there is none.
    var primaryRequirement: ConversationGateRequirement? {
        switch self {
        case .satisfied:                    return nil
        case .unsatisfied(_, let primary):  return primary
        }
    }
}

/// Both halves of a group chat's participation rules, evaluated together.
struct ConversationGate: Equatable {
    var listener: ConversationGateVerdict
    var speaker: ConversationGateVerdict

    /// The listener rule the chat advertises, met or not — what the panel names
    /// above Join Chat. The design states the requirement to someone who already
    /// satisfies it (node 10125:19102), so this is not the same as
    /// ``ConversationGateVerdict/primaryRequirement``, which only ever carries
    /// something the user is short of.
    var headline: ConversationGateRequirement?

    /// No rules to satisfy — every DM, and a group that doesn't gate anything.
    static let open = ConversationGate(listener: .satisfied, speaker: .satisfied, headline: nil)

    /// Whether every rule is met. True of a gated chat the user qualifies for,
    /// which is why this is not `self == .open` — that one also asserts the chat
    /// states no requirement.
    var isOpen: Bool { listener.isSatisfied && speaker.isSatisfied }
}

/// Evaluates a group chat's participation rules against what the user holds.
///
/// `rules` is nil for every non-group chat and for a group whose metadata hasn't
/// hydrated yet; both are open, as is an empty rule list — the contract
/// documents empty as "anyone can". `rates` is `RatesController.cachedRates`,
/// needed only to restate a requirement the server denominated in something
/// other than USD.
///
/// Speaker rules are evaluated on top of listener rules, not beside them: the
/// contract says a user must be able to listen before they can speak, so an
/// unmet listener rule makes the speaker verdict unsatisfied too, carrying both
/// rule sets. Evaluating them independently would let the client report "you
/// can't read this, but you could send" — a state the server never produces.
///
/// A single-mint requirement measures `StoredBalance.usdf`, the holding's USD
/// worth already resolved at store time, so it needs no rate at all. Not holding
/// the mint is a zero balance, not an error. `Session.hasSufficientFunds(for:)`
/// is deliberately not used: it is per-mint and debit-shaped, and nothing is
/// debited here — this is a holding requirement, so there is no fee and no
/// affordability check. `usernameGate` makes the same argument for the same
/// reason.
///
/// A requirement in a currency with no cached rate is treated as **satisfied**.
/// That is deliberately fail-open, and safe because the server enforces the same
/// rules and denies every read. Fail-closed would blur a chat the user actually
/// qualifies for on the strength of a number the client hasn't got — and if the
/// rate table never carries that currency, permanently. The cost is one denied
/// fetch on a race, which self-corrects on the next rate tick.
@MainActor
func conversationGate(
    session: some ConversationGateReading,
    rules: ConversationRules?,
    rates: [CurrencyCode: Rate]
) -> ConversationGate {
    guard let rules else { return .open }

    let listenerUnmet = rules.listener.compactMap { rule -> ConversationGateRequirement? in
        switch rule {
        case .staff:
            return session.isStaff ? nil : .staff
        case .minimumBalance(let requirement):
            return unmetBalance(requirement, session: session, rates: rates)
        }
    }

    let speakerUnmet = rules.speaker.compactMap { rule -> ConversationGateRequirement? in
        switch rule {
        case .staff:
            return session.isStaff ? nil : .staff
        case .minimumBalance(let requirement):
            return unmetBalance(requirement, session: session, rates: rates)
        }
    }

    let listener = verdict(for: listenerUnmet)
    // Speaking implies listening, so an unmet listener rule fails the speaker
    // verdict as well, carrying both sets.
    let speaker = verdict(for: listenerUnmet + speakerUnmet)

    return ConversationGate(
        listener: listener,
        speaker: speaker,
        headline: headline(for: rules.listener)
    )
}

/// The listener rule worth stating on the panel: the first minimum balance,
/// since it is the one with a number in it, falling back to the first rule.
private func headline(for rules: [ConversationListenerRule]) -> ConversationGateRequirement? {
    let requirements = rules.map { rule -> ConversationGateRequirement in
        switch rule {
        case .staff:
            return .staff
        case .minimumBalance(let requirement):
            return .minimumBalance(amount: requirement.amount, mint: requirement.mints.first)
        }
    }
    let balance = requirements.first {
        if case .minimumBalance = $0 { return true }
        return false
    }
    return balance ?? requirements.first
}

/// Returns the requirement when the user is short of it, or nil when it is met
/// — including when no rate is available to restate it (fail-open).
@MainActor
private func unmetBalance(
    _ requirement: MinimumBalanceRequirement,
    session: some ConversationGateReading,
    rates: [CurrencyCode: Rate]
) -> ConversationGateRequirement? {
    guard let required = requirement.amount.converted(to: .usd, rates: rates) else {
        return nil
    }
    // The contract allows at most one mint today; empty means every mint counts.
    let mint = requirement.mints.first
    let held = mint.map { session.balance(for: $0)?.usdf ?? .usd(0) } ?? session.totalBalance.usdfValue
    guard held >= required else {
        return .minimumBalance(amount: requirement.amount, mint: mint)
    }
    return nil
}

/// Picks the requirement to name: the first unmet minimum balance, since it is
/// the only one a user can act on, falling back to the first unmet rule.
private func verdict(for unmet: [ConversationGateRequirement]) -> ConversationGateVerdict {
    guard let first = unmet.first else { return .satisfied }
    let primary = unmet.first {
        if case .minimumBalance = $0 { return true }
        return false
    } ?? first
    return .unsatisfied(unmet: unmet, primary: primary)
}

// MARK: - Presentation -

/// What the bottom of a conversation renders, and whether the transcript is
/// blurred behind it.
enum ConversationGatePresentation: Equatable {
    /// Nothing gated — the ordinary composer.
    case open
    /// Listener rules unmet: blurred transcript, the requirement named, and a
    /// CTA when the requirement has one (node 10125:19153).
    case blocked(ConversationGateRequirement)
    /// Rules met for reading but not for sending: sharp transcript, the
    /// requirement in place of the composer.
    case readOnly(ConversationGateRequirement)

    /// Whether the transcript is blurred and its messages left unfetched.
    ///
    /// Only ``blocked``. Listener rules gate *reading*, so a user who satisfies
    /// them sees the real transcript even when the speaker rules shut the
    /// composer.
    var obscuresTranscript: Bool {
        switch self {
        case .open, .readOnly:  return false
        case .blocked:          return true
        }
    }

    /// Whether the composer is replaced by a gate panel.
    var replacesComposer: Bool {
        switch self {
        case .open:                return false
        case .blocked, .readOnly:  return true
        }
    }
}

/// Turns a rule verdict into what the screen draws.
///
/// Listener and speaker are weighed in that order because they nest: a user who
/// may not read cannot be offered a composer, so the listener verdict decides
/// the transcript first and the speaker verdict only ever narrows what is left.
func conversationGatePresentation(_ gate: ConversationGate) -> ConversationGatePresentation {
    switch gate.listener {
    case .unsatisfied(_, let primary):
        return .blocked(primary)
    case .satisfied:
        switch gate.speaker {
        case .unsatisfied(_, let primary):  return .readOnly(primary)
        case .satisfied:                    return .open
        }
    }
}
