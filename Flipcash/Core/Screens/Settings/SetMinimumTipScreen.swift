//
//  SetMinimumTipScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.minimum-tip")

/// Sets the minimum another user must pay to open a tip DM — "Minimum To Chat"
/// (node 10074:18892). Reached from My Account and from the You tab's "Finish
/// Your Profile" checklist.
///
/// Nothing is written until Save, so backing out discards the entry — the
/// behaviour node 9553:113241 asks for.
struct SetMinimumTipScreen: View {

    /// The floor, stated under the amount so a rejection is the exception
    /// rather than the flow. Client-side: the contract carries no minimum, and
    /// the server reports a breach as `ErrorSetMinDmChatInitFee.invalidAmount`,
    /// which lands on the same dialog.
    private static let minimumValue: Decimal = 1

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    /// True when this is a step in the profile checklist rather than a lone
    /// edit from My Account. Only the navigation payload distinguishes them —
    /// the screen itself is identical either way.
    let isSetupStep: Bool

    @State private var enteredAmount: String
    @State private var actionState: ButtonState = .normal
    @State private var dialog: DialogItem?
    @State private var submitTask: Task<Void, Never>?

    /// `initialAmount` is the fee already set, formatted by ``seed(fee:currency:)``
    /// at the call site. It seeds the field's state rather than being assigned
    /// once the screen is up: ``AmountField`` animates digits in as they are
    /// typed, and a seed applied after the first render plays that animation
    /// under the push — the placeholder floating out as the value floats in.
    init(isSetupStep: Bool, initialAmount: String) {
        self.isSetupStep = isSetupStep
        self._enteredAmount = State(initialValue: initialAmount)
    }

    private var currency: CurrencyCode { ratesController.balanceCurrency }

    private var minimum: FiatAmount {
        FiatAmount(value: Self.minimumValue, currency: currency)
    }

    /// The fee already on the profile, in the currency being entered. A fee set
    /// in another currency isn't comparable, so it seeds nothing.
    private var existingFee: FiatAmount? {
        guard let fee = sessionContainer.session.profile?.minDmChatInitFee,
              fee.currency == currency else { return nil }
        return fee
    }

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .minimumTip,
                enteredAmount: $enteredAmount,
                subtitle: .hidden,
                actionState: $actionState,
                actionEnabled: { _ in canSubmit },
                action: submit,
                header: AnyView(EnterAmountHeader(
                    enteredAmount: $enteredAmount,
                    hint: .description(
                        """
                        Choose how much someone must send you to start chatting. \
                        You can send it back if the conversation is worthwhile.
                        """
                    )
                ))
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        // Untitled by design (node 10074:18892): the description under the
        // amount says what the screen is for, so a title would repeat it.
        .dialog(item: $dialog)
        // The only continuation is a pop off a stack this screen has left.
        .onDisappear { submitTask?.cancel() }
    }

    // MARK: - Submission -

    /// Save stays dark until the entry is a real amount that differs from the
    /// fee already set — re-sending the current fee changes nothing. Amounts
    /// under the minimum keep it live and raise a dialog on tap (node
    /// 9544:20160), so the reason for the refusal is spelled out.
    private var canSubmit: Bool {
        guard let value = AmountValidator().validate(enteredAmount), value > 0 else { return false }
        return value != existingFee?.value
    }

    private func submit() {
        guard let value = AmountValidator().validate(enteredAmount),
              submitTask == nil else { return }

        guard value >= Self.minimumValue else {
            dialog = minimumDialog()
            return
        }

        let fee = FiatAmount(value: value, currency: currency)

        // Only a replacement is confirmed. A first fee gives nothing up, and
        // this screen is how the profile checklist sets one. Read off the
        // profile rather than `existingFee`, which is scoped to the currency
        // being entered — a fee set in another currency is still being replaced.
        guard sessionContainer.session.profile?.minDmChatInitFee != nil else {
            save(fee)
            return
        }

        dialog = .confirmProfileChange(.minimumTip) { save(fee) }
    }

    private func save(_ fee: FiatAmount) {
        actionState = .loading
        submitTask = Task {
            defer { submitTask = nil }

            do {
                try await container.flipClient.setMinDmChatInitFee(
                    fee,
                    owner: sessionContainer.session.ownerKeyPair
                )
                try await sessionContainer.session.updateProfile()

                actionState = .success
                // The same beat the other profile edits hold their checkmark
                // for, so the confirmation is seen before the screen leaves.
                try? await Task.delay(milliseconds: 500)

                guard !Task.isCancelled else { return }
                router.popTopmost()

            } catch {
                actionState = .normal
                guard !Task.isCancelled else { return }

                logger.error("Failed to set minimum tip", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Failed to set minimum tip")

                switch error as? ErrorSetMinDmChatInitFee {
                case .invalidAmount:
                    dialog = minimumDialog()
                case .ok, .denied, .unknown, .transportFailure, .cancelled, .rejected, .none:
                    dialog = .error(
                        title: "Couldn't Save Your Minimum",
                        subtitle: "Try again"
                    )
                }
            }
        }
    }

    private func minimumDialog() -> DialogItem {
        .info(
            title: "\(minimum.formatted()) Minimum",
            subtitle: "Please enter a higher amount"
        )
    }

    // MARK: - Seeding -

    /// The field's starting text for the fee already on the profile, so the
    /// screen opens showing what it is about to replace. Empty when there is no
    /// fee, or when the one set is in another currency — that amount isn't
    /// comparable to the one being entered, so it seeds nothing.
    static func seed(fee: FiatAmount?, currency: CurrencyCode) -> String {
        guard let fee, fee.currency == currency, fee.isPositive else { return "" }
        return AmountValidator().string(
            from: fee.value,
            fractionDigits: fractionDigits(for: fee)
        )
    }

    /// Whole fees seed without decimals ("5", not "5.00") so the field reads
    /// the way the user would have typed it.
    private static func fractionDigits(for fee: FiatAmount) -> Int {
        var value = fee.value
        var truncated = Decimal()
        NSDecimalRound(&truncated, &value, 0, .down)
        return truncated == value ? 0 : fee.currency.maximumFractionDigits
    }
}
