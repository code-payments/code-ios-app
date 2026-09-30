//
//  ProfileShareTitleTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@MainActor
@Suite("Profile share title")
struct ProfileShareTitleTests {

    @Test("A named profile is titled as an invitation to chat")
    func named() {
        #expect(TipCodeShareItem.profileTitle(for: "Ada") == "Chat with Ada on Flipcash")
    }

    @Test("A profile without a name shares untitled", arguments: [nil, ""] as [String?])
    func unnamed(displayName: String?) {
        #expect(TipCodeShareItem.profileTitle(for: displayName) == nil)
    }
}
