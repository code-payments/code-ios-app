//
//  CompactCurrencyFormatStyle.swift
//  FlipcashCore
//

import Foundation

/// A `FormatStyle` that formats numeric values as compact currency strings.
///
/// Uses the system's `.compactName` notation for large numbers and prepends
/// the currency symbol from `CurrencyCode`. Values below 100,000 are formatted
/// as whole numbers with grouping separators.
///
/// Usage with SwiftUI `Text`:
/// ```swift
/// Text(1_029_331.15, format: .compactCurrency(code: .usd))
/// // → "$1M"
///
/// Text(690_272.45, format: .compactCurrency(code: .usd))
/// // → "$690K"
///
/// Text(99_999, format: .compactCurrency(code: .usd))
/// // → "$100K"
/// ```
public struct CompactCurrencyFormatStyle: FormatStyle {

    public let currencyCode: CurrencyCode

    public init(code: CurrencyCode) {
        self.currencyCode = code
    }

    public func format(_ value: Double) -> String {
        let symbol = currencyCode.singleCharacterCurrencySymbols ?? ""
        let compact = Int(value).formatted(.number.notation(.compactName))
        return "\(symbol)\(compact)"
    }
}

// MARK: - FormatStyle Extension -

extension FormatStyle where Self == CompactCurrencyFormatStyle {
    /// Formats a number as a compact currency string (e.g. `$1M`, `$100K`, `$99,999`).
    public static func compactCurrency(code: CurrencyCode) -> CompactCurrencyFormatStyle {
        CompactCurrencyFormatStyle(code: code)
    }
}
