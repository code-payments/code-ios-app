//
//  DisplayCurrency.swift
//  FlipcashCore
//

import Foundation

/// The one currency the app shows money in — the Money tab selection — with the
/// rates that restate every other currency into it.
public struct DisplayCurrency: Equatable, Sendable {

    public let currency: CurrencyCode
    public let rates: [CurrencyCode: Rate]

    public init(currency: CurrencyCode, rates: [CurrencyCode: Rate]) {
        self.currency = currency
        self.rates = rates
    }

    public init(currency: CurrencyCode, rates: [Rate]) {
        self.init(
            currency: currency,
            rates: Dictionary(rates.map { ($0.currency, $0) }, uniquingKeysWith: { _, new in new })
        )
    }

    /// A payment as the viewer reads it. See ``ExchangedFiat/forViewer(in:rates:)``.
    public func amount(_ fiat: ExchangedFiat) -> FiatAmount {
        fiat.forViewer(in: currency, rates: rates)
    }

    /// A plain amount — a USD-priced boost or minimum, say — as the viewer reads
    /// it, or as it is when there is no rate to convert it with.
    public func amount(_ fiat: FiatAmount) -> FiatAmount {
        fiat.converted(to: currency, rates: rates) ?? fiat
    }

    /// A USD market figure — a market cap or its weekly change — restated and
    /// compacted, e.g. `$1.03M`.
    public func compactFormatted(usd: Double) -> String {
        let restated = amount(FiatAmount(value: Decimal(usd), currency: .usd))
        return restated.doubleValue.formatted(.compactCurrency(code: restated.currency))
    }
}

// MARK: - Shared Selection -

extension DisplayCurrency {

    private static let sharedKey = "com.flipcash.currency.displayCurrency"

    /// The Money tab selection as the app last wrote it to the App Group, so the
    /// notification extensions show amounts in it too. `nil` until the app has
    /// run once with this build.
    public static var sharedSelection: CurrencyCode? {
        get {
            UserDefaults(suiteName: NotificationPreviewCache.appGroup)?
                .string(forKey: sharedKey)
                .flatMap { CurrencyCode(rawValue: $0) }
        }
        set {
            UserDefaults(suiteName: NotificationPreviewCache.appGroup)?
                .set(newValue?.rawValue, forKey: sharedKey)
        }
    }
}
