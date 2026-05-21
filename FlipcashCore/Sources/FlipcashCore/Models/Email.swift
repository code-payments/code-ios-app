import Foundation

/// Email address whose initializer enforces the server-side proto pattern
/// at `flipcash.email.v1.EmailAddress`. Construction trims surrounding
/// whitespace; `value` is the canonical wire form.
public struct Email: Sendable {

    public let value: String

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.utf8.count <= 254 else {
            return nil
        }

        guard trimmed.wholeMatch(of: Self.pattern) != nil else {
            return nil
        }

        self.value = trimmed
    }

    /// Must equal the PGV pattern on
    /// `FlipcashAPI/Core/proto/email/v1/model.proto`.
    private nonisolated(unsafe) static let pattern = /^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/
}
