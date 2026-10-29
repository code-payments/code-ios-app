//
//  EditGroupBalanceRequirementModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-group-balance-requirement")

/// The state behind replacing one of a group's minimum balances, and its one save. Modelled on
/// ``EditGroupDescriptionModel``.
///
/// The entry is in the account's display currency and is saved in the join minimum's currency,
/// which the server requires every minimum to share, rounded to that currency's smallest unit. The
/// chat minimum is held in the join minimum's mints for the same reason.
@MainActor
@Observable
final class EditGroupBalanceRequirementModel {

    /// Where the save is. `.saved` is held by the screen for its checkmark before it pops.
    enum SaveState: Equatable {
        case normal
        case saving
        case saved
    }

    /// Why the save didn't go ahead or didn't land, shown as a dialog. Set to nil once shown.
    enum Failure: Equatable {
        /// The chat minimum isn't above the join minimum, given in the entry currency when a rate
        /// can restate it.
        case chatNotAboveJoin(join: FiatAmount)
        /// The server refused the rules, or they break a rule it enforces (a join minimum at or
        /// above the chat minimum).
        case invalidRules
        /// The creator doesn't meet the new rules.
        case rulesNotSatisfied
        case failed
    }

    let role: GroupBalanceRole

    /// The keypad's text, in ``currency``.
    var enteredAmount: String

    private(set) var state: SaveState = .normal
    var failure: Failure?

    /// The currency the amount is entered in.
    let currency: CurrencyCode

    @ObservationIgnored private let join: MinimumBalanceRequirement
    @ObservationIgnored private let speaker: MinimumBalanceRequirement?
    @ObservationIgnored private let rates: [CurrencyCode: Rate]
    @ObservationIgnored private let validator = AmountValidator()
    @ObservationIgnored private let satisfies: (ConversationRules) -> Bool?
    @ObservationIgnored private let saving: (FiatAmount?) async throws -> Void

    /// - Parameters:
    ///   - role: the minimum being replaced.
    ///   - join: the group's listener minimum, whose currency and mints every minimum shares.
    ///   - speaker: the group's own speaker minimum, or nil when it sets none.
    ///   - currency: the currency the amount is entered in.
    ///   - rates: what restates the entry in the join minimum's currency, and back.
    ///   - satisfies: whether the creator meets a set of minimums, or nil when their balance can't
    ///     be weighed against it.
    ///   - saving: submits the amount, in the join minimum's currency, or nil to remove the chat
    ///     minimum, and seats the chat's post-edit metadata.
    init(
        role: GroupBalanceRole,
        join: MinimumBalanceRequirement,
        speaker: MinimumBalanceRequirement?,
        currency: CurrencyCode,
        rates: [CurrencyCode: Rate],
        satisfies: @escaping (ConversationRules) -> Bool?,
        saving: @escaping (FiatAmount?) async throws -> Void
    ) {
        self.role = role
        self.join = join
        self.speaker = speaker
        self.currency = currency
        self.rates = rates
        self.satisfies = satisfies
        self.saving = saving
        let current = role == .join ? join : speaker
        self.enteredAmount = SetMinimumTipScreen.seed(
            fee: current?.amount.converted(to: currency, rates: rates),
            currency: currency
        )
    }

    /// The entry restated in the join minimum's currency and rounded to its smallest unit, or nil
    /// while it holds nothing a minimum can be set to: empty, zero, no rate to restate it, or below
    /// the currency's minimum transfer value.
    var amount: FiatAmount? {
        guard let value = validator.validate(enteredAmount), value > 0,
              let converted = FiatAmount(value: value, currency: currency).converted(to: join.amount.currency, rates: rates)
        else { return nil }
        let rounded = converted.roundedToSmallestUnit()
        return rounded.isPositive ? rounded : nil
    }

    /// Whether Save is enabled: a valid amount that differs from the one set.
    var canSave: Bool {
        guard state == .normal, let amount else { return false }
        let current = role == .join ? join : speaker
        return amount != current?.amount.roundedToSmallestUnit()
    }

    /// Whether the chat minimum can be removed, leaving none beyond joining.
    var canRemove: Bool {
        state == .normal && role == .chat && speaker != nil
    }

    /// Why the entry can't be sent, checked before the change is confirmed; nil when it can.
    var blocker: Failure? {
        guard let amount else { return nil }
        let joinAmount = join.amount.roundedToSmallestUnit()
        switch role {
        case .join:
            if let speaker, amount >= speaker.amount.roundedToSmallestUnit() {
                return .invalidRules
            }
        case .chat:
            // Both sides sit on the currency's smallest unit, so exceeding the join minimum means
            // exceeding it by at least the minimum transfer value.
            if amount <= joinAmount {
                return .chatNotAboveJoin(join: join.amount.converted(to: currency, rates: rates) ?? join.amount)
            }
        }
        guard satisfies(proposedRules(amount)) != false else { return .rulesNotSatisfied }
        return nil
    }

    /// Submits the entry. Failures land in ``failure``.
    func save() async {
        guard canSave, let amount else { return }
        if let blocker {
            failure = blocker
            return
        }
        await submit(amount)
    }

    /// Removes the chat minimum. Failures land in ``failure``.
    func remove() async {
        guard canRemove else { return }
        await submit(nil)
    }

    // MARK: - Private -

    /// The minimums the group would carry with `amount` saved for ``role``.
    private func proposedRules(_ amount: FiatAmount) -> ConversationRules {
        let listener = role == .join ? amount : join.amount
        let speaker = role == .chat ? amount : self.speaker?.amount
        return ConversationRules(
            listener: [.minimumBalance(MinimumBalanceRequirement(amount: listener, mints: join.mints))],
            speaker: speaker.map { [.minimumBalance(MinimumBalanceRequirement(amount: $0, mints: join.mints))] } ?? []
        )
    }

    private func submit(_ amount: FiatAmount?) async {
        state = .saving

        do {
            try await saving(amount)
            state = .saved

        } catch {
            state = .normal
            guard !Task.isCancelled else { return }
            logger.error("Failed to set group minimum balance", metadata: ["role": "\(role)", "error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to set group minimum balance")
            switch error {
            case ErrorEditChat.invalidRules:        failure = .invalidRules
            case ErrorEditChat.rulesNotSatisfied:   failure = .rulesNotSatisfied
            default:                                failure = .failed
            }
        }
    }
}
