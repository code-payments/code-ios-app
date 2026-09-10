//
//  StoreLocationTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Store location")
struct StoreLocationTests {

    private let owner = try! PublicKey(Data(repeating: 7, count: 32))

    private func location(shared: Bool = true) -> StoreLocation {
        let root = FileManager.default.temporaryDirectory
        return StoreLocation(
            directory: root.appendingPathComponent("shared-\(UUID().uuidString)"),
            legacyDirectory: root.appendingPathComponent("legacy-\(UUID().uuidString)"),
            isShared: shared
        )
    }

    // MARK: - File names -

    /// The names have to match what a pre-move install already wrote, or the migration looks in the
    /// right directory for the wrong files and silently concludes there is nothing to move.
    @Test func fileNamesFollowTheExistingConvention() {
        let location = location()
        let files = location.files(owner: owner)
        let base = "flipcash-\(owner.base58)"

        #expect(files.database.lastPathComponent == "\(base).sqlite")
        #expect(files.wal.lastPathComponent == "\(base).sqlite-wal")
        #expect(files.shm.lastPathComponent == "\(base).sqlite-shm")
    }

    /// The version file has no separator and no extension. It is the one name that looks like a typo
    /// and is not — changing it would orphan every existing install's recorded schema version, which
    /// reads as "version 0" and triggers a full store rebuild.
    @Test func versionFileNameHasNoSeparator() {
        let files = location().files(owner: owner)

        #expect(files.version.lastPathComponent == "flipcash-\(owner.base58)version")
        #expect(files.version.pathExtension.isEmpty)
    }

    @Test func filesLandInTheCurrentDirectory() {
        let location = location()
        let files = location.files(owner: owner)

        #expect(files.database.deletingLastPathComponent().path == location.directory.path)
        #expect(files.version.deletingLastPathComponent().path == location.directory.path)
    }

    @Test func legacyFilesLandInTheLegacyDirectory() {
        let location = location()
        let files = location.legacyFiles(owner: owner)

        #expect(files.database.deletingLastPathComponent().path == location.legacyDirectory.path)
        #expect(files.version.deletingLastPathComponent().path == location.legacyDirectory.path)
    }

    /// Same owner, same names, different directories — this is what makes the migration a move
    /// rather than a rename.
    @Test func currentAndLegacyDifferOnlyByDirectory() {
        let location = location()

        #expect(location.files(owner: owner).database.lastPathComponent
                == location.legacyFiles(owner: owner).database.lastPathComponent)
        #expect(location.files(owner: owner).database.path
                != location.legacyFiles(owner: owner).database.path)
    }

    @Test func differentOwnersGetDifferentFiles() throws {
        let location = location()
        let other = try PublicKey(Data(repeating: 9, count: 32))

        #expect(location.files(owner: owner).database.path != location.files(owner: other).database.path)
    }

    // MARK: - Resolution -

    /// An unresolvable App Group must not be fatal. The app keeps working out of the legacy
    /// directory; what it loses is the extension's ability to see the store.
    @Test func missingContainerFallsBackToLegacy() {
        let legacy = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)")

        let location = StoreLocation.resolved(
            legacyDirectory: legacy,
            containerURL: { _ in nil }
        )

        #expect(location.isShared == false)
        #expect(location.directory.path == legacy.path)
        #expect(location.legacyDirectory.path == legacy.path)
    }

    /// When the container is missing, current and legacy are the same directory — so a migration
    /// asked to run finds its source and destination identical and has to treat that as a no-op
    /// rather than moving a file onto itself.
    @Test func fallbackMakesCurrentAndLegacyIdentical() {
        let legacy = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)")

        let location = StoreLocation.resolved(
            legacyDirectory: legacy,
            containerURL: { _ in nil }
        )

        #expect(location.files(owner: owner) == location.legacyFiles(owner: owner))
    }

    @Test func resolvedContainerBecomesTheStoreDirectory() {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-\(UUID().uuidString)")
        let legacy = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)")

        let location = StoreLocation.resolved(
            legacyDirectory: legacy,
            containerURL: { _ in container }
        )

        #expect(location.isShared)
        #expect(location.directory.path == container.path)
        #expect(location.legacyDirectory.path == legacy.path)
    }

    /// The group identifier is passed through untouched — a typo here would silently give the app a
    /// container the extensions do not share.
    @Test func resolvedPassesTheAppGroupToTheLookup() {
        var requested: String?
        _ = StoreLocation.resolved(containerURL: { group in
            requested = group
            return nil
        })

        #expect(requested == StoreLocation.appGroup)
        #expect(StoreLocation.appGroup == "group.com.flipcash.shared")
    }
}
