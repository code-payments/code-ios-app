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
            return entered.nativeAmount.roundedToSmallestUnit() >= fee
        case .preset(let presets):
            return presets.meetsMinimum(entered)
        }
    }
}

extension TipFloor {

    /// The floor for the tip that *opens* a DM with a recipient: the fee they
    /// charge, restated in `currency`, falling back to the regional preset when
    /// they charge nothing or their fee is below it. Nil when neither is known.
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
        // Rounded up: a half-up floor can land under the fee, pass `isMet`,
        // and be denied by the server.
        if let fee = recipientFee?.converted(to: currency, rates: rates, roundingUp: true), fee.isPositive {
            // Every tip carries the regional minimum, so a fee under it would
            // pass the fee check and be denied for the minimum.
            if let presets, !clears(fee, presets, rates: rates) {
                return .preset(presets)
            }
            return .recipientFee(fee)
        }
        return systemMinimum(presets: presets)
    }

    /// Whether `fee` meets the preset row's minimum, compared the way
    /// `TipPresets.meetsMinimum` compares an entry. A fee that can't be
    /// restated in the row's currency keeps its own floor.
    private static func clears(_ fee: FiatAmount, _ presets: UserFlags.TipPresets, rates: [CurrencyCode: Rate]) -> Bool {
        guard let restated = fee.converted(to: presets.currency, rates: rates) else { return true }
        return restated.value >= presets.minimum
    }

    /// The regional minimum every tip carries, regardless of recipient.
    public static func systemMinimum(presets: UserFlags.TipPresets?) -> TipFloor? {
        presets.map { .preset($0) }
    }
}
