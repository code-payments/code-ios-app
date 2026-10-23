//
//  ExchangedFiat+ViewerAmount.swift
//  FlipcashCore
//

import Foundation

// MARK: - Viewer Currency -

extension ExchangedFiat {

    /// This amount restated in `display`, the one currency the app shows money in.
    /// A 7,500 ARS tip reads as its $5 to a viewer in dollars.
    ///
    /// A USDF payment carries its own USD value on-chain, fixed at the moment it
    /// settled, so it converts from that: $5 of USDF stays $5 however far the peso
    /// has moved since. Any other mint has no such anchor — `onChainAmount` holds
    /// that mint's own quarks, not dollars — so it crosses through today's `rates`
    /// instead. With no usable rate on either side the amount shows as it moved.
    ///
    /// Unrounded; the formatter rounds half-even to the display currency's minor
    /// units, which is what `test-vectors/viewer_amount.json` pins.
    public func forViewer(in display: CurrencyCode, rates: [CurrencyCode: Rate]) -> FiatAmount {
        guard nativeAmount.currency != display else { return nativeAmount }

        guard let displayRate = rates.usable(display), let usd = settledUSDValue(rates: rates) else {
            return nativeAmount
        }

        return usd.converting(to: displayRate)
    }

    /// The entry's value in USD, or `nil` when it can't be established. See
    /// ``forViewer(in:rates:)``.
    ///
    /// Deliberately not `usdfValue`: an activity's rate is synthesized from
    /// `nativeAmount / onChainAmount` for a bonded mint, so dividing back through
    /// it returns the token quantity rather than dollars.
    private func settledUSDValue(rates: [CurrencyCode: Rate]) -> FiatAmount? {
        if mint == .usdf {
            return .usd(onChainAmount.decimalValue)
        }

        guard let rate = rates.usable(nativeAmount.currency) else { return nil }
        return nativeAmount.convertingToUSD(rate: rate)
    }
}

// MARK: - Signing -

extension FiatAmount {

    /// This amount formatted with `signPrefix` ahead of it, or formatted as-is when
    /// the value already carries its own sign.
    ///
    /// Activity amounts arrive as magnitudes with their direction alongside them,
    /// which is why the row supplies a sign at all; a value that is genuinely
    /// negative formats its own "-", and prefixing that as well would read
    /// "--$5.00".
    public func formatted(signPrefix: String?) -> String {
        guard let signPrefix, value >= 0 else { return formatted() }
        return signPrefix + formatted()
    }
}
