//
//  StartChattingFee.swift
//  Flipcash
//

import FlipcashCore

/// What it costs to open a chat with a user, as their profile and the conversation CTA name it.
///
/// Derived from the same inputs as `SendAmountViewModel.tipFloor(in:)`, so the amount shown is the
/// one the amount screen enforces.
enum StartChattingFee {

    /// The fee `recipientFee` charges, restated in `currency` and rounded up, falling back to the
    /// regional preset minimum. Nil when neither is known.
    static func amount(
        recipientFee: FiatAmount?,
        presets: UserFlags.TipPresets?,
        currency: CurrencyCode,
        rates: [CurrencyCode: Rate]
    ) -> FiatAmount? {
        TipFloor.toOpenDM(
            recipientFee: recipientFee,
            presets: presets,
            in: currency,
            rates: rates
        )?.displayed
    }

    /// The fee for `profile`, in the user's balance currency.
    @MainActor
    static func amount(for profile: Profile?, session: Session, ratesController: RatesController) -> FiatAmount? {
        let currency = ratesController.balanceCurrency
        return amount(
            recipientFee: profile?.minDmChatInitFee,
            presets: session.userFlags?.tipPresets(for: currency),
            currency: currency,
            rates: ratesController.cachedRates
        )
    }
}
