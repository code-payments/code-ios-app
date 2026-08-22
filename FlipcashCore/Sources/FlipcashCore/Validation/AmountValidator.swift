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

    /// Renders `value` back into the string the keypad itself would have
    /// produced — the inverse of `validate(_:)`. For the rare correction a flow
    /// makes on the user's behalf, such as dropping an entry to the maximum its
    /// balance can fund; ordinary display goes through `FiatAmount.formatted()`.
    ///
    /// Truncates rather than rounds, so a correction derived as a ceiling can't
    /// be nudged back above it.
    public func string(from value: Decimal, fractionDigits: Int) -> String {
        let separator = self.separator ?? Self.localizedDecimalSeparator
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = separator
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .down
        return formatter.string(from: value as NSDecimalNumber) ?? ""
    }
}
