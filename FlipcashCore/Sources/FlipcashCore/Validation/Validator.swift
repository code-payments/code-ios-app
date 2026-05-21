import Foundation

/// Validates and canonicalises a free-form `String` input.
///
/// `validate(_:)` returns the canonical form (e.g. trimmed, normalised) when
/// the input passes, or `nil` when it doesn't. The canonical form is the
/// value safe to submit to a server contract; the raw input is left to the
/// caller for display.
///
/// `Output` is per-validator: `String` for length/regex checks, value types
/// like `Phone` for richer parses.
public protocol Validator<Output>: Sendable {
    associatedtype Output
    func validate(_ input: String) -> Output?
}
