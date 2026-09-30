//
//  DisplayNameValidator.swift
//  FlipcashCore
//

import Foundation

/// Validates a profile display name: 1–64 Unicode scalars of any script.
///
/// Returns the name trimmed of leading and trailing whitespace. With `asciiOnly`,
/// the trimmed name may also contain only `A-Z`, `a-z`, `0-9`, and U+0020.
public struct DisplayNameValidator: Validator {

    /// PGV `max_len` from `FlipcashAPI/Core/proto/profile/v1/profile_service.proto`
    /// counts Unicode scalars, not grapheme clusters — one ZWJ emoji spends seven.
    public static let maxScalars = 64

    private let asciiOnly: Bool

    /// Creates a validator; `asciiOnly` restricts names to ASCII letters, digits, and spaces.
    public init(asciiOnly: Bool = false) {
        self.asciiOnly = asciiOnly
    }

    public func validate(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= Self.maxScalars else {
            return nil
        }

        if asciiOnly, !trimmed.unicodeScalars.allSatisfy(Self.isASCIIAlphanumericOrSpace) {
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

    private static func isASCIIAlphanumericOrSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x30...0x39, 0x41...0x5A, 0x61...0x7A: true
        default: false
        }
    }
}
