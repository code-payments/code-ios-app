//
//  ExchangedFiat+ViewerAmount.swift
//  FlipcashCore
//

import Foundation

/// What an activity row shows for its amount.
///
/// - `viewer` is the entry in the currency the viewer reads money in — always the
///   row's headline.
/// - `transferred` is what actually moved, set only when the payment was
///   denominated in a currency that isn't the viewer's; `nil` when the two are the
///   same and a second line would just repeat the first.
public struct ViewerAmount: Equatable, Hashable, Sendable {

    public let viewer: FiatAmount
    public let transferred: FiatAmount?

    public init(viewer: FiatAmount, transferred: FiatAmount?) {
        self.viewer = viewer
        self.transferred = transferred
    }
}

// MARK: - Viewer Currency -

extension ExchangedFiat {

    /// Restates this amount in the viewer's own currency (`preferredRate`'s),
    /// keeping what was actually transferred alongside it when the two differ — a
    /// 7,500 ARS tip reads as its $5 to a viewer in dollars, with the pesos
    /// underneath.
    ///
    /// A USDF payment carries its own USD value on-chain, fixed at the moment it
    /// settled, so it converts from that: $5 of USDF stays $5 however far the peso
    /// has moved since. Any other mint has no such anchor — `onChainAmount` holds
    /// that mint's own quarks, not dollars — so it crosses through today's `rates`
    /// instead, and falls back to the transferred amount alone when the source
    /// currency has no rate to cross with.
    public func forViewer(preferredRate: Rate, rates: [CurrencyCode: Rate]) -> ViewerAmount {
        let transferred = nativeAmount
        guard transferred.currency != preferredRate.currency else {
            return ViewerAmount(viewer: transferred, transferred: nil)
        }

        guard preferredRate.fx > 0, let usd = settledUSDValue(rates: rates) else {
            return ViewerAmount(viewer: transferred, transferred: nil)
        }

        return ViewerAmount(viewer: usd.converting(to: preferredRate), transferred: transferred)
    }

    /// The entry's value in USD, or `nil` when it can't be established. See
    /// ``forViewer(preferredRate:rates:)``.
    ///
    /// Deliberately not `usdfValue`: an activity's rate is synthesized from
    /// `nativeAmount / onChainAmount` for a bonded mint, so dividing back through
    /// it returns the token quantity rather than dollars.
    private func settledUSDValue(rates: [CurrencyCode: Rate]) -> FiatAmount? {
        if mint == .usdf {
            return .usd(onChainAmount.decimalValue)
        }

        guard let rate = rates[nativeAmount.currency], rate.fx > 0 else { return nil }
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
