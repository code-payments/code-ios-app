//
//  ChatMediaConstraints.swift
//  FlipcashCore
//

import Foundation

/// Which `UploadPolicy.mimeTypeConstraints` entry governs an upload — the first one, in policy
/// order, whose pattern matches. Pure string matching; the caller owns fetching the policy
/// (`BlobService.getUploadPolicy`).
public enum ChatMediaConstraints {

    /// Returns the index of the first pattern in `patterns` (already in policy order) that
    /// matches `mimeType`, or nil if none does. A pattern is `"type/subtype"`, `"type/*"`, or
    /// `"*/*"`.
    public static func firstMatchIndex(patterns: [String], mimeType: String) -> Int? {
        let mimeParts = mimeType.split(separator: "/", maxSplits: 1)
        guard mimeParts.count == 2 else { return nil }
        let (mimeType0, mimeType1) = (mimeParts[0], mimeParts[1])

        return patterns.firstIndex { pattern in
            if pattern == "*/*" { return true }
            let patternParts = pattern.split(separator: "/", maxSplits: 1)
            guard patternParts.count == 2 else { return false }
            let (patternType, patternSubtype) = (patternParts[0], patternParts[1])
            guard patternType == mimeType0 else { return false }
            return patternSubtype == "*" || patternSubtype == mimeType1
        }
    }
}
