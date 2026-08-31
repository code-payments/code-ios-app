//
//  CompactCurrencyFormatStyle.swift
//  FlipcashCore
//

import Foundation

/// A `FormatStyle` that formats numeric values as compact currency strings —
/// the `FormatStyle` entry point onto ``FiatAmount/formattedAbbreviated(maxDigits:)``,
/// for the `Double` figures (market caps, deltas) SwiftUI formats inline.
///
/// Sub-unit precision is dropped before formatting: at this scale it is noise,
/// and a market cap reads `$200`, not `$200.17`.
///
/// Usage with SwiftUI `Text`:
/// ```swift
/// Text(1_029_331.15, format: .compactCurrency(code: .usd))
/// // → "$1.03M"
///
/// Text(690_272.45, format: .compactCurrency(code: .usd))
/// // → "$690K"
///
/// Text(99_999, format: .compactCurrency(code: .usd))
/// // → "$100K"
///
/// Text(-12_400, format: .compactCurrency(code: .usd))
/// // → "-$12.4K"
/// ```
public struct CompactCurrencyFormatStyle: FormatStyle {

    public let currencyCode: CurrencyCode

    public init(code: CurrencyCode) {
        self.currencyCode = code
    }

    public func format(_ value: Double) -> String {
        FiatAmount(value: Decimal(Int(value)), currency: currencyCode)
            .formattedAbbreviated()
    }
}

// MARK: - FormatStyle Extension -

extension FormatStyle where Self == CompactCurrencyFormatStyle {
    /// Formats a number as a compact currency string (e.g. `$1M`, `$100K`, `$999`).
    public static func compactCurrency(code: CurrencyCode) -> CompactCurrencyFormatStyle {
        CompactCurrencyFormatStyle(code: code)
    }
}
