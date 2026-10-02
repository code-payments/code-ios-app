//
//  AppMeta.swift
//  FlipcashCore
//

import Foundation

public enum AppMeta {

    /// Stand-in returned when the host has no Info.plist value, as in a package test host.
    public static let unknown = "unknown"

    /// The app's marketing version, or ``unknown`` when the host bundle doesn't declare one.
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? unknown
    }

    /// The app's build number, or ``unknown`` when the host bundle doesn't declare one.
    ///
    /// Deliberately not a numeric stand-in: `SessionAuthenticator.requiresUpgrade` parses this and
    /// treats an unparseable value as "allow access", whereas `"0"` would parse and read as a build
    /// older than any server minimum, gating the app behind a forced upgrade it can never satisfy.
    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? unknown
    }

    /// The git commit stamp the app was built from, or ``unknown`` when the host bundle doesn't
    /// declare one. Parse it with ``BuildCommit`` for display.
    public static var commit: String {
        Bundle.main.object(forInfoDictionaryKey: "FCGitCommit") as? String ?? unknown
    }

    /// The You screen's version footer, in the format Android's footer uses.
    ///
    /// Two lines, `Version <version> • Build <build>` over the commit label followed by
    /// ` • <track>` when there is one. Without a commit it falls back to the single line
    /// `Version <version> • Build <build>`, with the track appended the same way.
    public static func versionFooter(
        version: String = version,
        build: String = build,
        commit: BuildCommit,
        track: String? = nil
    ) -> String {
        let trackSuffix = track.map { " • \($0)" } ?? ""
        let versionLine = "Version \(version) • Build \(build)"
        guard let label = commit.label else {
            return versionLine + trackSuffix
        }
        return versionLine + "\n" + label + trackSuffix
    }
}
