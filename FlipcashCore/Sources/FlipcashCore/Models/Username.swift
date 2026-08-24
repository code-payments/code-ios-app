//
//  Username.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// A user's unique handle on Flipcash, without a leading `@`.
///
/// The character set matches X — letters, digits and underscores — except that
/// a handle is always lowercase. Public: the server returns it for any user,
/// not just the caller.
public struct Username: Codable, Equatable, Hashable, Sendable {

    /// The handle as the server stores it: lowercase, 2–15 characters.
    public let value: String

    /// Returns the handle `string` names, or `nil` when it isn't well formed.
    /// Strict rather than normalizing — an uppercase or over-long input is a
    /// caller error, not something to silently rewrite.
    public init?(_ string: String) {
        guard string.wholeMatch(of: Self.pattern) != nil else {
            return nil
        }

        self.value = string
    }

    // Mirrors the `validate.rules.string.pattern` on `common.v1.Username`;
    // keep the two in step when the contract moves.
    private nonisolated(unsafe) static let pattern = /^[a-z0-9_]{2,15}$/
}

// MARK: - Codable -

extension Username {

    /// Encodes as a bare string rather than a wrapper object, so a persisted
    /// profile reads as `"username": "ted"`.
    public init(from decoder: Decoder) throws {
        // Deliberately does not re-validate: the value passed ``init(_:)`` when
        // it was first built, and a throw here would fail the decode of the
        // whole enclosing profile blob over a cosmetic handle.
        self.value = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension Username: CustomStringConvertible {
    public var description: String {
        value
    }
}

// MARK: - Proto -

extension Username {

    /// Returns the handle `proto` carries, or `nil` when the user hasn't
    /// claimed one — the server leaves the field unset, which decodes to an
    /// empty value.
    init?(_ proto: Flipcash_Common_V1_Username) {
        self.init(proto.value)
    }
}
