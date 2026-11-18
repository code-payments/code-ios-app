//
//  UsernameValidator.swift
//  FlipcashCore
//

import Foundation

/// Validates a handle typed into the username field: lowercases the input and
/// drops the `@` a handle is shown with, then holds it to the `Username` contract.
///
/// That normalising lives here rather than in `Username.init?` so the model stays
/// strict — a handle reaching it uppercase or prefixed is still a caller error.
/// This is the only place a typed handle is rewritten before it reaches the model.
public struct UsernameValidator: Validator {

    /// Why an input was rejected. The claim screen raises a different dialog for
    /// each, so the reason is part of the contract rather than a logging detail.
    public enum Failure: Equatable, Sendable {
        case tooShort
        case tooLong
        case invalidCharacters
    }

    /// The bounds a claimed handle must fit. The minimum is `Username`'s own; the
    /// maximum is a product cap below the 30 that `common.v1.Username` allows, so
    /// handles the server assigns can be longer than any a user may claim.
    /// Public because the rejection copy names them.
    public static let minimumLength = 2
    public static let maximumLength = 15

    private let lengthCap: Int

    /// Holds input to `maximumLength`, or to `Username.maximumLength` for a field that
    /// looks up an existing handle rather than claiming one.
    public init(maximumLength: Int = Self.maximumLength) {
        self.lengthCap = maximumLength
    }

    /// The handle `input` names once normalised, or `nil` when it isn't well
    /// formed. This exact value is what gets submitted; the raw input stays on
    /// screen.
    public func validate(_ input: String) -> Username? {
        claimable(normalized(input))
    }

    /// Which rule `input` breaks, or `nil` when it breaks none.
    ///
    /// Runs the same check ``validate(_:)`` does first, so a `nil` here and a non-nil there can
    /// never disagree. Past that, length is reported ahead of the character
    /// set: "too short" explains a one-letter input better than "invalid
    /// characters" would, and an over-long input is over-long whatever it is
    /// made of.
    public func failure(for input: String) -> Failure? {
        let candidate = normalized(input)

        guard claimable(candidate) == nil else { return nil }

        if candidate.count < Self.minimumLength { return .tooShort }
        if candidate.count > lengthCap { return .tooLong }
        return .invalidCharacters
    }

    /// The handle `candidate` names within this validator's cap. `Username` also accepts the
    /// contract's longer server-assigned handles, so a claim's lower cap is held here.
    private func claimable(_ candidate: String) -> Username? {
        guard candidate.count <= lengthCap else { return nil }
        return Username(candidate)
    }

    /// Lowercased, stripped of surrounding whitespace, and of one leading `@`.
    /// A paste carries all three — a handle copied out of a profile arrives as
    /// `@taylor` — and none is worth rejecting someone over. Only one `@` goes:
    /// `@@taylor` is not a handle anyone has, and the field never adds one.
    private func normalized(_ input: String) -> String {
        var candidate = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if candidate.hasPrefix("@") {
            candidate.removeFirst()
        }
        return candidate
    }
}
