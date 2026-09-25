//
//  BuildCommitTests.swift
//  FlipcashCoreTests
//

import Testing
@testable import FlipcashCore

@Suite("BuildCommit — parsing and formatting the build's commit stamp")
struct BuildCommitTests {

    private static let sha = "2acfecffeb4d1c3b8e0f9a7d6c5b4a3928170615"

    @Test("A clean stamp keeps the full SHA and displays its first 10 characters")
    func cleanStamp() {
        let commit = BuildCommit(Self.sha)
        #expect(commit.sha == Self.sha)
        #expect(commit.isDirty == false)
        #expect(commit.display == "2acfecffeb")
    }

    @Test("A dirty stamp keeps the full SHA and suffixes the display")
    func dirtyStamp() {
        let commit = BuildCommit(Self.sha + "-dirty")
        #expect(commit.sha == Self.sha)
        #expect(commit.isDirty)
        #expect(commit.display == "2acfecffeb-dirty")
    }

    @Test("An uppercase SHA is normalized to git's lowercase")
    func uppercaseStamp() {
        #expect(BuildCommit(Self.sha.uppercased()).sha == Self.sha)
    }

    @Test(
        "Anything that isn't a 40-character SHA displays as unknown",
        arguments: [
            AppMeta.unknown,
            "",
            "$(GIT_COMMIT_SHA)",
            "-dirty",
            "2acfecffeb",
            "2acfecffeb-dirty",
            "2acfecffeb4d1c3b8e0f9a7d6c5b4a39281706150",
            "zacfecffeb4d1c3b8e0f9a7d6c5b4a3928170615",
        ]
    )
    func unusableStamp(stamp: String) {
        let commit = BuildCommit(stamp)
        #expect(commit.sha == nil)
        #expect(commit.isDirty == false)
        #expect(commit.display == AppMeta.unknown)
    }
}
