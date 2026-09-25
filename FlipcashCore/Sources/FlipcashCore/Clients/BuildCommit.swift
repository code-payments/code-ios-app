//
//  BuildCommit.swift
//  FlipcashCore
//

import Foundation

/// The git commit a build was made from, parsed from the stamp in ``AppMeta/commit``.
///
/// The stamp is a 40-character SHA, suffixed `-dirty` when a local build had uncommitted
/// changes. Anything else, including ``AppMeta/unknown``, parses as an unknown commit.
public struct BuildCommit: Equatable, Sendable {

    /// Characters of the SHA shown in ``display``, matched by Android's version footer.
    public static let displayLength = 10

    private static let dirtySuffix = "-dirty"

    /// The full 40-character SHA, or `nil` when the build carried no usable stamp.
    public let sha: String?

    /// Whether the build was made from a working tree with uncommitted changes.
    public let isDirty: Bool

    /// Parses a stamp as written by `Scripts/write_commit_xcconfig`.
    public init(_ stamp: String) {
        let dirty = stamp.hasSuffix(Self.dirtySuffix)
        let candidate = dirty ? String(stamp.dropLast(Self.dirtySuffix.count)) : stamp

        if candidate.count == 40, candidate.allSatisfy(\.isHexDigit) {
            sha = candidate.lowercased()
            isDirty = dirty
        } else {
            sha = nil
            isDirty = false
        }
    }

    /// The commit as the version footer shows it: the first ``displayLength`` characters of
    /// the SHA, `-dirty` when it applies, or ``AppMeta/unknown``.
    public var display: String {
        guard let sha else { return AppMeta.unknown }
        return String(sha.prefix(Self.displayLength)) + (isDirty ? Self.dirtySuffix : "")
    }
}
