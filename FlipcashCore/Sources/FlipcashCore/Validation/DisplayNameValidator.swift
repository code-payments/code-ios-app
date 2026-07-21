//
//  DisplayNameValidator.swift
//  FlipcashCore
//

import Foundation

/// Validates a profile display name: 1–64 Unicode scalars of any script.
///
/// Returns the name trimmed of leading and trailing whitespace.
public struct DisplayNameValidator: Validator {

    /// PGV `max_len` from `FlipcashAPI/Core/proto/profile/v1/profile_service.proto`
    /// counts Unicode scalars, not grapheme clusters — one ZWJ emoji spends seven.
    public static let maxScalars = 64

    public init() {}

    public func validate(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= Self.maxScalars else {
            return nil
        }

        return trimmed
    }

    /// Returns how many more Unicode scalars the name accepts, negative once it
    /// has already exceeded the limit.
    public func remaining(in input: String) -> Int {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.maxScalars - trimmed.unicodeScalars.count
    }
}
