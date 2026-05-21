import Foundation

public struct EmailValidator: Validator {

    public init() {}

    public func validate(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.utf8.count <= 254 else {
            return nil
        }

        guard trimmed.wholeMatch(of: Self.pattern) != nil else {
            return nil
        }

        return trimmed
    }

    /// Must equal the PGV pattern on
    /// `FlipcashAPI/Core/proto/email/v1/model.proto`.
    private nonisolated(unsafe) static let pattern = /^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/
}
