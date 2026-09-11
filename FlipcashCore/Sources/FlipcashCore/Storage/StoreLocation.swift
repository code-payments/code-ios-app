//
//  StoreLocation.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Where the SQLite store lives, and where it used to live.
///
/// The store started in the app's private Application Support directory, which the notification
/// extensions cannot open — separate processes, separate containers. Moving it into the App Group
/// container is what lets the extension write messages that the app will later read.
///
/// This type is paths only. It resolves the container and names the files; it never opens or moves
/// anything. That keeps it testable against temporary directories, and keeps `FlipcashCore` free of
/// a SQLite dependency it does not otherwise have.
public struct StoreLocation: Sendable {

    /// The App Group shared by the app and both notification extensions.
    public static let appGroup = NotificationPreviewCache.appGroup

    /// Where the store lives now.
    public let directory: URL

    /// Where the store lived before the App Group move, and where a pre-move install still has it.
    public let legacyDirectory: URL

    /// False when the App Group container could not be resolved and `directory` fell back to
    /// `legacyDirectory`.
    ///
    /// That happens when the entitlement is missing or the group is not provisioned for the running
    /// build — a build configuration problem rather than a runtime condition to recover from.
    /// Falling back keeps the app working, with an extension that cannot see the store, instead of
    /// refusing to launch. The flag is here so the caller can report it: `FlipcashCore` has no
    /// reporting channel of its own.
    public let isShared: Bool

    public init(directory: URL, legacyDirectory: URL, isShared: Bool) {
        self.directory = directory
        self.legacyDirectory = legacyDirectory
        self.isShared = isShared
    }

    /// Resolves the App Group container, falling back to the legacy directory when it is missing.
    ///
    /// `containerURL` is injected rather than called directly because the lookup it wraps is not
    /// consistent across platforms: on iOS `containerURL(forSecurityApplicationGroupIdentifier:)`
    /// returns nil when the app lacks the entitlement, but on macOS — where this package's tests
    /// run — it returns a constructed path for any identifier, provisioned or not. The nil branch is
    /// therefore unreachable from a test that passes a bogus group name, and the seam is what makes
    /// the fallback testable at all.
    public static func resolved(
        appGroup: String = StoreLocation.appGroup,
        legacyDirectory: URL = .applicationSupportDirectory,
        containerURL: (String) -> URL? = {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    ) -> StoreLocation {
        guard let container = containerURL(appGroup) else {
            return StoreLocation(
                directory: legacyDirectory,
                legacyDirectory: legacyDirectory,
                isShared: false
            )
        }

        // The store goes in the container root rather than a subdirectory. The root is guaranteed to
        // exist once the container resolves, which removes a create-directory step — and its failure
        // mode — from the migration path. The file names are already owner-scoped and prefixed, so
        // they cannot collide with `ChatPreviews/`.
        return StoreLocation(
            directory: container,
            legacyDirectory: legacyDirectory,
            isShared: true
        )
    }

    // MARK: - Files -

    /// The four files that make up one owner's store within a single directory.
    ///
    /// SQLite derives the `-wal` and `-shm` names from the main file rather than being told them, so
    /// these are not independently choosable paths. They are named here because the migration and
    /// `Database.deleteStore` both have to account for them.
    public struct Files: Sendable, Equatable {
        public let database: URL
        public let wal: URL
        public let shm: URL
        public let version: URL

        public init(database: URL, wal: URL, shm: URL, version: URL) {
            self.database = database
            self.wal = wal
            self.shm = shm
            self.version = version
        }
    }

    /// The owner's store files in the current directory.
    public func files(owner: PublicKey) -> Files {
        Self.files(owner: owner, in: directory)
    }

    /// The owner's store files in the pre-move directory.
    public func legacyFiles(owner: PublicKey) -> Files {
        Self.files(owner: owner, in: legacyDirectory)
    }

    private static func files(owner: PublicKey, in directory: URL) -> Files {
        let base = "flipcash-\(owner.base58)"
        return Files(
            database: directory.appendingPathComponent("\(base).sqlite"),
            wal: directory.appendingPathComponent("\(base).sqlite-wal"),
            shm: directory.appendingPathComponent("\(base).sqlite-shm"),
            // No separator before "version", and no extension. This is the name a pre-move install
            // already has on disk, so the migration has to look for exactly this to find it.
            version: directory.appendingPathComponent("\(base)version")
        )
    }
}
