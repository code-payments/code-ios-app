import Foundation
import Logging

/// Redacts metadata values matching known sensitive formats:
/// - Base58 strings longer than 32 characters (likely Solana keys)
/// - Email addresses
/// - Phone number patterns
public struct PatternRedactor: LogMiddleware {

    // Base58 alphabet (Bitcoin variant used by Solana)
    private static let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    private nonisolated(unsafe) static let emailPattern = try! Regex("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}")

    // Matches common phone formats: +1234567890, (123) 456-7890, 123-456-7890
    private nonisolated(unsafe) static let phonePattern = try! Regex("(?:\\+\\d{1,3}[\\s.-]?)?(?:\\(?\\d{3}\\)?[\\s.-]?)?\\d{3}[\\s.-]?\\d{4}")

    public init() {}

    public func process(_ entry: inout LogEntry) -> Bool {
        guard var metadata = entry.metadata, !metadata.isEmpty else {
            return true
        }

        for (key, value) in metadata {
            if case .string(let str) = value, shouldRedact(str) {
                metadata[key] = "[REDACTED]"
            }
        }

        entry.metadata = metadata
        return true
    }

    private func shouldRedact(_ value: String) -> Bool {
        // Base58 strings longer than 32 chars (likely Solana public keys)
        if value.count > 32 && value.unicodeScalars.allSatisfy({ Self.base58Chars.contains($0) }) {
            return true
        }

        // Email addresses
        if value.firstMatch(of: Self.emailPattern) != nil {
            return true
        }

        // Phone numbers (only if the string looks like it's primarily a phone number)
        if value.count <= 20, value.firstMatch(of: Self.phonePattern) != nil {
            return true
        }

        return false
    }
}
