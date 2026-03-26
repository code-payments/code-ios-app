import Logging

/// Redacts metadata values whose keys contain sensitive words.
///
/// Matches are case-insensitive. Any key containing words like
/// "token", "key", "secret", etc. will have its value replaced
/// with `[REDACTED]`.
public struct SensitiveKeyRedactor: LogMiddleware {

    private static let sensitivePatterns: [String] = [
        "token", "key", "secret", "password", "seed", "mnemonic", "phone", "email",
    ]

    public init() {}

    public func process(_ entry: inout LogEntry) -> Bool {
        guard var metadata = entry.metadata, !metadata.isEmpty else {
            return true
        }

        for (key, _) in metadata {
            let lowered = key.lowercased()
            if Self.sensitivePatterns.contains(where: { lowered.contains($0) }) {
                metadata[key] = "[REDACTED]"
            }
        }

        entry.metadata = metadata
        return true
    }
}
