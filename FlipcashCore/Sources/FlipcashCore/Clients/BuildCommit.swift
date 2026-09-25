//
//  BuildCommit.swift
//  FlipcashCore
//

import Foundation

/// The git commit a build was made from, parsed from the stamp in ``AppMeta/commit``.
///
/// The stamp is a 40-character SHA, suffixed `*` when a local build had uncommitted changes to
/// tracked files. Anything else, including ``AppMeta/unknown``, parses as no commit.
public struct BuildCommit: Equatable, Sendable {

    /// Characters of the SHA shown in ``label``, matched by Android's version footer.
    public static let labelLength = 10

    private static let dirtyMarker = "*"

    /// The full 40-character SHA, or `nil` when the build carried no usable stamp.
    public let sha: String?

    /// Whether the build was made with uncommitted changes to tracked files.
    public let isDirty: Bool

    /// Parses a stamp as written by `Scripts/write_commit_xcconfig`.
    public init(_ stamp: String) {
        let dirty = stamp.hasSuffix(Self.dirtyMarker)
        let candidate = dirty ? String(stamp.dropLast(Self.dirtyMarker.count)) : stamp

        if candidate.count == 40, candidate.allSatisfy(\.isHexDigit) {
            sha = candidate.lowercased()
            isDirty = dirty
        } else {
            sha = nil
            isDirty = false
        }
    }

    /// The commit as the version footer shows it: the first ``labelLength`` characters of the
    /// SHA with `*` appended for a dirty build, or `nil` when there is no commit.
    public var label: String? {
        guard let sha else { return nil }
        return String(sha.prefix(Self.labelLength)) + (isDirty ? Self.dirtyMarker : "")
    }
}
