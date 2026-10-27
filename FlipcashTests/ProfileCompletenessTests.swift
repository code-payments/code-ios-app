//
//  ProfileCompletenessTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Profile completeness and featured-groups section")
struct ProfileCompletenessTests {

    private static func picture() -> ProfilePicture {
        let blobID = BlobID(uuid: UUID())
        return ProfilePicture(blobID: blobID, thumbnailBlobID: blobID)
    }

    private static func profile(photo: Bool, cover: Bool, bio: String?, username: Username? = nil) -> Profile {
        Profile(
            displayName: "Mike",
            phone: Optional<Phone>.none,
            email: nil,
            profilePicture: photo ? picture() : nil,
            username: username,
            bio: bio,
            coverPicture: cover ? picture() : nil
        )
    }

    @Test("Missing photo, cover or a non-blank bio leaves the profile incomplete", arguments: [
        (false, false, nil),
        (true, true, ""),
        (true, true, "   "),
        (true, false, "hi"),
        (false, true, "hi"),
    ] as [(Bool, Bool, String?)])
    func incomplete(photo: Bool, cover: Bool, bio: String?) {
        #expect(!Self.profile(photo: photo, cover: cover, bio: bio).isComplete)
    }

    @Test("Photo, cover and bio complete the profile without a username")
    func complete() {
        #expect(Self.profile(photo: true, cover: true, bio: "hi", username: nil).isComplete)
    }

    @Test("Own profile shows the section with no groups; others hide it")
    func visibility() {
        #expect(FeaturedGroupsSection.isVisible(groupCount: 0, showsEmptyState: true))
        #expect(FeaturedGroupsSection.isVisible(groupCount: 2, showsEmptyState: true))
        #expect(!FeaturedGroupsSection.isVisible(groupCount: 0, showsEmptyState: false))
        #expect(FeaturedGroupsSection.title == "Favorite Community Chats")
        #expect(FeaturedGroupsSection.emptyText == "None yet")
    }

    @Test("Own profile says None yet only once favorites are known empty")
    func ownEmptyState() {
        #expect(FeaturedGroupsSection.ownProfileShowsEmptyState(hasUsername: false, isLoaded: false))
        #expect(!FeaturedGroupsSection.ownProfileShowsEmptyState(hasUsername: true, isLoaded: false))
        #expect(FeaturedGroupsSection.ownProfileShowsEmptyState(hasUsername: true, isLoaded: true))
    }

    @Test("The edit button is accented and asks to complete until the profile is complete")
    func editButton() {
        let incomplete = EditProfileButtonState(isProfileComplete: false)
        #expect(incomplete.title == "Complete Your Profile")
        #expect(incomplete.isAccented)
        let complete = EditProfileButtonState(isProfileComplete: true)
        #expect(complete.title == "Edit Profile")
        #expect(!complete.isAccented)
    }

    @Test("Favorites count as loaded only after a read or a save")
    func favoritesLoaded() async {
        let unloaded = FeaturedGroups(fetching: { _ in [] })
        #expect(!unloaded.isLoaded)
        unloaded.replace(with: [])
        #expect(unloaded.isLoaded)

        let loading = FeaturedGroups(fetching: { _ in [] })
        let read = await loading.load(username: Username("mike")!)
        #expect(read && loading.isLoaded)

        struct Failure: Error {}
        let failing = FeaturedGroups(fetching: { _ in throw Failure() })
        _ = await failing.load(username: Username("mike")!)
        #expect(!failing.isLoaded)
    }
}
