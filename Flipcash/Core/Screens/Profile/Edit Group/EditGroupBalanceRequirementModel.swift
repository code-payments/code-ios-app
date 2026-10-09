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
/// The entry is in the account's display currency and is saved in USD, the conversion
/// ``MinimumBalanceAmountSheet`` applies when a group is created: the gate weighs holdings by
/// their USD worth, so a USD requirement needs no rate to enforce. The requirement keeps the mint
/// it already names; a group with no requirement gets one across all holdings, as
/// ``NewPublicGroupModel`` builds it.
@MainActor
@Observable
final class EditGroupBalanceRequirementModel {

    /// Where the save is. `.saved` is held by the screen for its checkmark before it pops.
    enum SaveState: Equatable {
        case normal
        case saving
        case saved
    }

    /// Why the save didn't land, shown as a dialog. Set to nil once shown.
    enum Failure: Equatable {
        /// The contract has no way to change a group's rules yet.
        case unavailable
        case failed
    }

    let role: GroupBalanceRole

    /// The keypad's text, in ``currency``.
    var enteredAmount: String

    private(set) var state: SaveState = .normal
    var failure: Failure?

    /// The currency the amount is entered in.
    let currency: CurrencyCode

    @ObservationIgnored private let current: MinimumBalanceRequirement?
    @ObservationIgnored private let rates: [CurrencyCode: Rate]
    @ObservationIgnored private let validator = AmountValidator()
    @ObservationIgnored private let saving: (MinimumBalanceRequirement) async throws -> Void

    /// - Parameters:
    ///   - role: the minimum being replaced.
    ///   - current: the requirement the role shows now. For ``GroupBalanceRole/chat`` on a group
    ///     with no speaker rule, that is the join requirement, which the chat minimum falls back
    ///     to; saving writes an explicit speaker rule.
    ///   - currency: the currency the amount is entered in.
    ///   - rates: what restates the entry in USD, and the current requirement in ``currency``.
    ///   - saving: submits the requirement and seats the chat's post-edit metadata.
    init(
        role: GroupBalanceRole,
        current: MinimumBalanceRequirement?,
        currency: CurrencyCode,
        rates: [CurrencyCode: Rate],
        saving: @escaping (MinimumBalanceRequirement) async throws -> Void
    ) {
        self.role = role
        self.current = current
        self.currency = currency
        self.rates = rates
        self.saving = saving
        self.enteredAmount = SetMinimumTipScreen.seed(
            fee: current?.amount.converted(to: currency, rates: rates),
            currency: currency
        )
    }

    /// The entry as the requirement it would save, or nil while it holds nothing a requirement can
    /// be set to: empty, zero, no rate to restate it in USD, or small enough to round away there.
    var requirement: MinimumBalanceRequirement? {
        guard let value = validator.validate(enteredAmount), value > 0,
              let usd = FiatAmount(value: value, currency: currency).converted(to: .usd, rates: rates),
              usd.isPositive else { return nil }
        return MinimumBalanceRequirement(amount: usd, mints: current?.mints ?? [])
    }

    /// Whether Save is enabled: a valid amount that differs, at display precision, from the one set.
    var canSave: Bool {
        guard state == .normal, let requirement else { return false }
        guard let current = current?.amount.converted(to: .usd, rates: rates) else { return true }
        return requirement.amount.roundedToSmallestUnit() != current.roundedToSmallestUnit()
    }

    /// Submits the requirement. Failures land in ``failure``.
    func save() async {
        guard canSave, let requirement else { return }

        state = .saving

        do {
            try await saving(requirement)
            state = .saved

        } catch ErrorSetGroupMinimumBalance.unavailable {
            // The stub throws this on every save, so it is expected rather than reported.
            state = .normal
            logger.info("Group minimum balance edit unavailable", metadata: ["role": "\(role)"])
            failure = .unavailable

        } catch {
            state = .normal
            guard !Task.isCancelled else { return }
            logger.error("Failed to set group minimum balance", metadata: ["role": "\(role)", "error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to set group minimum balance")
            failure = .failed
        }
    }
}
