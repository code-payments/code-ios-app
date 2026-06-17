//
//  SubstitutionApplier.swift
//  FlipcashCore
//

import Foundation

/// Applies positional `{0}`, `{1}`, ... substitutions to a template string.
public enum SubstitutionApplier {

    /// Replaces each `{i}` placeholder in `template` with `resolutions[i]`.
    /// Placeholders without a matching index are left in place.
    public static func apply(template: String, resolutions: [String]) -> String {
        var result = template
        for (index, resolution) in resolutions.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: resolution)
        }
        return result
    }
}
