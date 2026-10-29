//
//  HomeTabLandingTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("Home tab landing") @MainActor
struct HomeTabLandingTests {

    @Test("Home opens on Chat after every login")
    func homeOpensOnChat() {
        #expect(HomeTab.initial == .chat)
    }
}
