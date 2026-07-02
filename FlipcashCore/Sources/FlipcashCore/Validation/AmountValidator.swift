import Foundation

/// Validates a keypad-entered amount string, canonicalising the locale
/// decimal separator to "." before parsing. `Decimal(string:)` alone stops
/// at a "," separator and silently drops the fraction.
public struct AmountValidator: Validator {

    /// The decimal separator the device keypad emits.
    public nonisolated static var localizedDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    private let separator: String?

    /// Pass a fixed `separator` to make parsing locale-independent (tests);
    /// by default the device separator is read at each validation.
    public init(separator: String? = nil) {
        self.separator = separator
    }

    public func validate(_ input: String) -> Decimal? {
        guard !input.isEmpty else { return nil }
        let separator = self.separator ?? Self.localizedDecimalSeparator
        return Decimal(string: input.replacingOccurrences(of: separator, with: "."))
    }
}
