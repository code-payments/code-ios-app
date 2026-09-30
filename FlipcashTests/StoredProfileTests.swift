//
//  StoredProfileTests.swift
//  FlipcashTests
//

import Foundation
import FlipcashCore
import FlipcashStore
import Testing

@Suite("Database.storedProfile")
struct StoredProfileTests {

    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stored-profile-\(UUID().uuidString).sqlite")
    }

    @Test("returns the profile saved in another owner's store")
    func returnsSavedProfile() throws {
        let url = makeURL()
        let profile = Profile(
            displayName: "Ted Lasso",
            phone: Optional<Phone>.none,
            email: nil,
            userID: UUID(),
            username: Username("ted")
        )

        let database = try Database(url: url)
        try database.insertProfile(profile)
        try database.close()

        let stored = try #require(Database.storedProfile(at: url))
        #expect(stored.username == Username("ted"))
        #expect(stored.displayName == "Ted Lasso")
        #expect(stored.userID == profile.userID)
    }

    @Test("returns nil when the owner has no store on disk, without creating one")
    func missingStore() {
        let url = makeURL()

        #expect(Database.storedProfile(at: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("returns nil for a store with no saved profile")
    func storeWithoutProfile() throws {
        let url = makeURL()
        try Database(url: url).close()

        #expect(Database.storedProfile(at: url) == nil)
    }

    /// The read must never create tables in, or otherwise write to, another owner's store.
    @Test("returns nil for a store without the profile table, and leaves it without one")
    func storeWithoutTables() throws {
        let url = makeURL()
        FileManager.default.createFile(atPath: url.path, contents: nil)

        #expect(Database.storedProfile(at: url) == nil)

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        #expect(size == 0)
    }
}
