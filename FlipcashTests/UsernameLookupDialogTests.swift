//
//  UsernameLookupDialogTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Username lookup dialogs")
struct UsernameLookupDialogTests {

    @Test("A handle nobody has claimed is informational, not an error")
    func notFound_isInformational() {
        let item = DialogItem.usernameNotFound
        #expect(item.style == .standard)
        #expect(item.title == "Username Not Found")
        #expect(item.subtitle == "Please try a different username")
    }

    @Test("The not-found dialog offers a single OK")
    func notFound_singleAction() {
        let item = DialogItem.usernameNotFound
        #expect(item.actions.count == 1)
        #expect(item.actions[0].title == "OK")
    }

    @Test("A thrown notFound still lands on the not-found copy")
    func thrownNotFound_readsAsNotFound() {
        let item = DialogItem.usernameLookup(for: ErrorFetchProfile.notFound)
        #expect(item.style == .standard)
        #expect(item.title == "Username Not Found")
    }

    @Test("A fetch that didn't land apologises instead of claiming the handle is free")
    func transportFailure_apologises() {
        let item = DialogItem.usernameLookup(for: ErrorFetchProfile.transportFailure)
        #expect(item.style == .destructive)
        #expect(item.title == "Couldn't Look Up Username")
        #expect(item.subtitle == "Please check your connection and try again")
    }

    @Test("An error the screen doesn't model apologises rather than misreporting a miss")
    func unknownError_apologises() {
        struct Boom: Error {}
        let item = DialogItem.usernameLookup(for: Boom())
        #expect(item.style == .destructive)
        #expect(item.title == "Couldn't Look Up Username")
    }
}
