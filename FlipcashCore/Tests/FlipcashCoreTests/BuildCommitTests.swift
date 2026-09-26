//
//  BuildCommitTests.swift
//  FlipcashCoreTests
//

import Testing
@testable import FlipcashCore

@Suite("BuildCommit — parsing the build's commit stamp and formatting the version footer")
struct BuildCommitTests {

    private static let sha = "2acfecffeb4d1c3b8e0f9a7d6c5b4a3928170615"

    @Test("A clean stamp keeps the full SHA and labels it with the first 10 characters")
    func cleanStamp() {
        let commit = BuildCommit(Self.sha)
        #expect(commit.sha == Self.sha)
        #expect(commit.isDirty == false)
        #expect(commit.label == "2acfecffeb")
    }

    @Test("A dirty stamp keeps the full SHA and appends an asterisk to the label")
    func dirtyStamp() {
        let commit = BuildCommit(Self.sha + "*")
        #expect(commit.sha == Self.sha)
        #expect(commit.isDirty)
        #expect(commit.label == "2acfecffeb*")
    }

    @Test("An uppercase SHA is normalized to git's lowercase")
    func uppercaseStamp() {
        #expect(BuildCommit(Self.sha.uppercased()).sha == Self.sha)
    }

    @Test(
        "Anything that isn't a 40-character SHA has no label",
        arguments: [
            AppMeta.unknown,
            "",
            "$(GIT_COMMIT_SHA)",
            "*",
            "2acfecffeb",
            "2acfecffeb*",
            "2acfecffeb4d1c3b8e0f9a7d6c5b4a3928170615-dirty",
            "2acfecffeb4d1c3b8e0f9a7d6c5b4a39281706150",
            "zacfecffeb4d1c3b8e0f9a7d6c5b4a3928170615",
        ]
    )
    func unusableStamp(stamp: String) {
        let commit = BuildCommit(stamp)
        #expect(commit.sha == nil)
        #expect(commit.isDirty == false)
        #expect(commit.label == nil)
    }

    // MARK: - Footer -

    @Test("The footer puts the commit on its own line")
    func footerWithCommit() {
        let footer = AppMeta.versionFooter(version: "2026.9.3", build: "272", commit: BuildCommit(Self.sha))
        #expect(footer == "Version 2026.9.3 • Build 272\n2acfecffeb")
    }

    @Test("A track follows the commit on the second line")
    func footerWithCommitAndTrack() {
        let footer = AppMeta.versionFooter(version: "2026.9.3", build: "272", commit: BuildCommit(Self.sha + "*"), track: "beta")
        #expect(footer == "Version 2026.9.3 • Build 272\n2acfecffeb* • beta")
    }

    @Test("Without a commit the footer is the old single line")
    func footerWithoutCommit() {
        let footer = AppMeta.versionFooter(version: "2026.9.3", build: "272", commit: BuildCommit(AppMeta.unknown))
        #expect(footer == "Version 2026.9.3 • Build 272")
    }

    @Test("Without a commit a track stays on the single line")
    func footerWithoutCommitWithTrack() {
        let footer = AppMeta.versionFooter(version: "2026.9.3", build: "272", commit: BuildCommit(AppMeta.unknown), track: "beta")
        #expect(footer == "Version 2026.9.3 • Build 272 • beta")
    }
}
