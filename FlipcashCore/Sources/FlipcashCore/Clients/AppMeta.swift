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
}
