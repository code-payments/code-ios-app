import Foundation
import Logging

/// Redacts metadata values matching known sensitive formats:
/// - Base58 strings longer than 32 characters (likely Solana keys) → first 4 + last 4 chars
/// - Email addresses → first char of local part + `..` + domain (e.g. `r..@gmail.com`)
/// - Phone numbers → `***-***-` + last 4 digits
public struct PatternRedactor: LogMiddleware {

    // Base58 alphabet (Bitcoin variant used by Solana)
    private static let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    // Captures: 1=first char of local, 2=rest of local, 3=@domain
    private nonisolated(unsafe) static let emailPattern = #/([a-zA-Z0-9._%+-])([a-zA-Z0-9._%+-]*)(@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/#

    // Matches phone formats: +1234567890, (123) 456-7890, 123-456-7890, 1234567890.
    // Captures: 1=last 4 digits.
    private nonisolated(unsafe) static let phonePattern = #/(?:\+\d{1,3}[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)?\d{3}[\s.-]?(\d{4})/#

    public init() {}

    public func process(_ entry: inout LogEntry) -> Bool {
        guard var metadata = entry.metadata, !metadata.isEmpty else {
            return true
        }

        for (key, value) in metadata {
            if case .string(let str) = value, let redacted = redact(str) {
                metadata[key] = .string(redacted)
            }
        }

        entry.metadata = metadata
        return true
    }

    /// Returns a redacted version of the string, or `nil` if no redaction is needed.
    /// Each metadata value is expected to *be* the sensitive thing (per the logging
    /// rule in CLAUDE.md), so all matches are anchored to the whole string.
    private func redact(_ value: String) -> String? {
        // Pure base58 strings longer than 32 chars (likely Solana public keys).
        if value.count > 32 && value.unicodeScalars.allSatisfy({ Self.base58Chars.contains($0) }) {
            return "\(value.prefix(4))...\(value.suffix(4))"
        }

        // Email: <first char>..<domain>. Skip the regex entirely if there's no @.
        if value.contains("@"), let match = value.wholeMatch(of: Self.emailPattern) {
            return "\(match.output.1)..\(match.output.3)"
        }

        // Phone: ***-***-<last 4 digits>. Shortest valid format is 7 digits.
        if value.count >= 7, let match = value.wholeMatch(of: Self.phonePattern) {
            return "***-***-\(match.output.1)"
        }

        return nil
    }
}
