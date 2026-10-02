//
//  MarketCapExplainerViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashStore

/// Drives "How Market Cap Works": loads the currency's supply and holdings,
/// builds the pure ``MarketCapExplainer`` calculator, and formats its output.
@Observable
final class MarketCapExplainerViewModel {

    enum LoadingState {
        case loading
        case loaded(name: String, MarketCapExplainer)
        case unavailable
    }

    private(set) var loadingState: LoadingState = .loading

    /// Slider position in 0...1 along the log-reserve track.
    var trackPosition: Double = 0 {
        didSet { selection = explainer?.stop(atTrackPosition: trackPosition) ?? selection }
    }

    /// The point on the curve the slider is on.
    private(set) var selection: MarketCapExplainer.Stop?

    @ObservationIgnored private let mint: PublicKey
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController

    init(mint: PublicKey, session: Session, ratesController: RatesController) {
        self.mint = mint
        self.session = session
        self.ratesController = ratesController
    }

    var explainer: MarketCapExplainer? {
        if case .loaded(_, let explainer) = loadingState { return explainer }
        return nil
    }

    var name: String {
        if case .loaded(let name, _) = loadingState { return name }
        return ""
    }

    func load() async {
        guard case .loading = loadingState else { return }
        do {
            let metadata = try await session.fetchMintMetadata(mint: mint)
            guard let supply = metadata.supplyFromBonding else {
                loadingState = .unavailable
                return
            }
            let held = session.balance(for: mint)?.quarks
            guard let explainer = MarketCapExplainer(
                todaySupplyQuarks: supply,
                heldQuarks: (held ?? 0) > 0 ? held : nil
            ) else {
                loadingState = .unavailable
                return
            }
            loadingState = .loaded(name: metadata.name, explainer)
            let today = explainer.todayStop
            selection = today
            trackPosition = explainer.trackPosition(of: today)
        } catch {
            loadingState = .unavailable
        }
    }

    // MARK: - Formatting

    /// The user's preferred in-app currency, the same rate the balance and
    /// appreciation pills use. The curve math stays in USD; only display converts.
    private var displayRate: Rate { ratesController.rateForBalanceCurrency() }

    private func display(_ usd: Decimal) -> FiatAmount {
        FiatAmount.usd(usd).converting(to: displayRate)
    }

    /// A reserve, compact, in the display currency: `$22.7K`, `$10M`.
    func reserveText(_ reserve: Decimal) -> String {
        display(reserve).formattedAbbreviated()
    }

    /// A per-token price: more decimals the smaller it is.
    func priceText(_ price: Decimal) -> String {
        let digits = price < Decimal(string: "0.1")! ? 5 : (price < 1 ? 4 : 2)
        let converted = display(price)
        return NumberFormatter.fiat(currency: converted.currency, minimumFractionDigits: 2, maximumFractionDigits: digits)
            .string(from: converted.value as NSDecimalNumber) ?? ""
    }

    func worthText(at stop: MarketCapExplainer.Stop) -> String {
        guard let worth = explainer?.worth(at: stop) else { return "–" }
        return display(worth).formatted()
    }

    func percentText(_ fraction: Decimal?) -> String {
        guard let fraction else { return "–" }
        // A small non-zero share must not read as "0%". Exact zero still does.
        if fraction > 0, fraction < Decimal(string: "0.0001")! { return "<0.01%" }
        return fraction.formatted(.percent.precision(.fractionLength(0...2)))
    }

    func tokensText(_ tokens: Decimal?) -> String {
        guard let tokens else { return "–" }
        return tokens.formatted(.number.precision(.fractionLength(0)))
    }

    /// The existing balance-card pill text (`+$12.34`), in the display currency.
    var appreciationText: String {
        guard let balance = session.balance(for: mint) else { return "–" }
        let (value, isPositive) = balance.computeAppreciation(with: ratesController.rateForBalanceCurrency())
        return value.nativeAmount.signedAppreciationText(isPositive: isPositive)
    }

    enum AppreciationSign { case positive, negative, zero }

    /// Zero when the delta is too small to display, so it never reads as a gain or loss.
    var appreciationSign: AppreciationSign {
        guard let balance = session.balance(for: mint) else { return .zero }
        let (value, isPositive) = balance.computeAppreciation(with: ratesController.rateForBalanceCurrency())
        guard value.nativeAmount.hasDisplayableValue else { return .zero }
        return isPositive ? .positive : .negative
    }
}

extension FiatAmount {
    /// The signed appreciation pill text. A sub-cent delta reads as positive so
    /// it never renders "-$0.00".
    func signedAppreciationText(isPositive: Bool) -> String {
        let positive = isPositive || !hasDisplayableValue
        return (positive ? "+" : "-") + formatted()
    }
}
