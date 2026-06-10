import Foundation

/// Validates free-form text against a maximum length, rejecting blank
/// (empty or whitespace-only) input. Returns the text unchanged.
public struct LengthValidator: Validator {

    public let maxLength: Int

    public init(maxLength: Int) {
        self.maxLength = maxLength
    }

    public func validate(_ input: String) -> String? {
        guard !input.allSatisfy(\.isWhitespace), input.count <= maxLength else {
            return nil
        }

        return input
    }
}
