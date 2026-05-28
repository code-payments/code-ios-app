//
//  SubstitutionApplier.swift
//  FlipcashCore
//

import Foundation

/// Applies positional `{0}`, `{1}`, ... substitutions to a template string.
public enum SubstitutionApplier {

    /// String used when a resolution is `nil`. Never produces an E.164.
    public static let unresolvedFallback = "Someone you know"

    /// Replaces each `{i}` placeholder in `template` with `resolutions[i]`.
    /// `nil` entries use ``unresolvedFallback``. Placeholders without a
    /// matching index are left in place.
    public static func apply(template: String, resolutions: [String?]) -> String {
        var result = template
        for (index, resolution) in resolutions.enumerated() {
            let value = resolution ?? unresolvedFallback
            result = result.replacingOccurrences(of: "{\(index)}", with: value)
        }
        return result
    }
}
