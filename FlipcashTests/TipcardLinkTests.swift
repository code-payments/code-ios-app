//
//  TipcardLinkTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Tipcard link")
struct TipcardLinkTests {

    private let userID = UUID(uuidString: "B0CED1D2-3F4A-4B5C-8D9E-0F1A2B3C4D5E")!

    @Test("An unclaimed card links by lowercase uuid")
    func tipcard_noUsername_uuidForm() {
        let url = URL.tipcard(for: userID, username: nil)
        #expect(url.absoluteString == "https://flipcash.com/tip/b0ced1d2-3f4a-4b5c-8d9e-0f1a2b3c4d5e")
    }

    @Test("A claimed card links by handle, at the root and without an @")
    func tipcard_username_handleForm() {
        let url = URL.tipcard(for: userID, username: Username("taylor"))
        #expect(url.absoluteString == "https://flipcash.com/taylor")
    }
}
