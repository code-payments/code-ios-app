//
//  TipFloor.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The minimum a tip has to clear, and where that minimum came from.
///
/// Two floors exist and they are not interchangeable: a recipient can charge a
/// fee to be written to, and the server publishes a regional minimum every tip
/// carries. The fee buys the conversation, so it applies to exactly one
/// payment — the tip that opens the DM. Which of the two applies is the
/// caller's decision; this type only states and enforces the one it holds.
public enum TipFloor: Equatable, Sendable {

    /// The recipient's own fee to open a DM with them, already restated in the
    /// currency the amount is being entered in.
    case recipientFee(FiatAmount)

    /// The server's regional minimum for the entry currency, or its USD row.
    case preset(UserFlags.TipPresets)

    /// The floor as it reads under the amount entry.
    public var displayed: FiatAmount {
        switch self {
        case .recipientFee(let fee):
            fee
        case .preset(let presets):
            FiatAmount(value: presets.minimum, currency: presets.currency)
        }
    }

    /// Whether `entered` clears this floor. Both sides compare at display
    /// precision — what we display is what we accept.
    public func isMet(by entered: ExchangedFiat) -> Bool {
        switch self {
        case .recipientFee(let fee):
            // The fee is resolved into the entry currency by `toOpenDM`, so a
            // mismatch here means no rate reached it. Comparing across
            // currencies would trap; the server remains the authority instead.
            guard entered.nativeAmount.currency == fee.currency else { return true }
            let value = entered.nativeAmount.value.rounded(to: fee.currency.maximumFractionDigits)
            return value >= fee.value
        case .preset(let presets):
            return presets.meetsMinimum(entered)
        }
    }
}

extension TipFloor {

    /// The floor for the tip that *opens* a DM with a recipient: the fee they
    /// charge, restated in `currency`, falling back to the regional preset when
    /// they charge nothing. Nil when neither is known.
    ///
    /// The fallback also covers a fee that can't be converted — stating a floor
    /// in a currency the entry isn't using would be worse than stating the
    /// regional one.
    public static func toOpenDM(
        recipientFee: FiatAmount?,
        presets: UserFlags.TipPresets?,
        in currency: CurrencyCode,
        rates: [CurrencyCode: Rate]
    ) -> TipFloor? {
        if let fee = recipientFee?.converted(to: currency, rates: rates), fee.isPositive {
            return .recipientFee(fee)
        }
        return systemMinimum(presets: presets)
    }

    /// The regional minimum every tip carries, regardless of recipient.
    public static func systemMinimum(presets: UserFlags.TipPresets?) -> TipFloor? {
        presets.map { .preset($0) }
    }
}
