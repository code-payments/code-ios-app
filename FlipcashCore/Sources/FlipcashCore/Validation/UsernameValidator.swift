//
//  UsernameValidator.swift
//  FlipcashCore
//

import Foundation

/// Validates a handle typed into the username field: lowercases the input, then
/// holds it to the `Username` contract.
///
/// Lowercasing lives here rather than in `Username.init?` so the model stays
/// strict — a handle reaching it uppercase is still a caller error. This is the
/// only place a typed handle is rewritten before it reaches the model.
public struct UsernameValidator: Validator {

    /// Why an input was rejected. The claim screen raises a different dialog for
    /// each, so the reason is part of the contract rather than a logging detail.
    public enum Failure: Equatable, Sendable {
        case tooShort
        case tooLong
        case invalidCharacters
    }

    /// Mirrors `Username`'s own bounds, which come from the `validate.rules`
    /// on `common.v1.Username`. Public because the rejection copy names them.
    /// `UsernameValidatorTests` pins them to what `Username` actually accepts,
    /// so the two can't drift apart unnoticed.
    public static let minimumLength = 2
    public static let maximumLength = 15

    public init() {}

    /// The handle `input` names once normalised, or `nil` when it isn't well
    /// formed. This exact value is what gets submitted; the raw input stays on
    /// screen.
    public func validate(_ input: String) -> Username? {
        Username(normalized(input))
    }

    /// Which rule `input` breaks, or `nil` when it breaks none.
    ///
    /// Asks ``validate(_:)`` first, so a `nil` here and a non-nil there can
    /// never disagree. Past that, length is reported ahead of the character
    /// set: "too short" explains a one-letter input better than "invalid
    /// characters" would, and an over-long input is over-long whatever it is
    /// made of.
    public func failure(for input: String) -> Failure? {
        let candidate = normalized(input)

        guard Username(candidate) == nil else { return nil }

        if candidate.count < Self.minimumLength { return .tooShort }
        if candidate.count > Self.maximumLength { return .tooLong }
        return .invalidCharacters
    }

    /// Lowercased and stripped of surrounding whitespace. A paste carries both,
    /// and neither is worth rejecting someone over.
    private func normalized(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
