import Foundation

/// Validates and canonicalises a free-form `String` input.
///
/// `validate(_:)` returns the canonical form (trimmed, normalised) when the
/// input passes, or `nil` when it doesn't. Callers submit the canonical
/// form to server contracts; the raw input is left for display.
public protocol Validator<Output>: Sendable {
    associatedtype Output: Sendable
    func validate(_ input: String) -> Output?
}
