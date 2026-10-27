//
//  EditProfileCopyTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Edit Profile copy")
struct EditProfileCopyTests {

    @Test("Cover chip follows whether a cover is set")
    func coverChip() {
        #expect(EditProfileCopy.coverChip(hasCover: false) == "Add cover photo")
        #expect(EditProfileCopy.coverChip(hasCover: true) == "Change cover")
    }

    @Test("Photo caption follows whether a photo is set")
    func photoCaption() {
        #expect(EditProfileCopy.photoCaption(hasPhoto: false) == "Add profile photo")
        #expect(EditProfileCopy.photoCaption(hasPhoto: true) == "Change photo")
    }

    @Test("Username value shows any handle, nil when there is none")
    func usernameValue() throws {
        let assigned = try #require(Username("mike_l_2"))
        #expect(EditProfileCopy.usernameValue(assigned) == "@mike_l_2")
        #expect(EditProfileCopy.usernameValue(nil) == nil)
    }
}
