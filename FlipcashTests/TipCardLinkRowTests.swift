//
//  TipCardLinkRowTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Tip card link row display text")
struct TipCardLinkRowTests {

    @Test("A uuid is still clipped to a stub")
    func displayText_uuid_clipped() {
        let url = URL(string: "https://app.flipcash.com/tip/b0ced1d2-3f4a-4b5c-8d9e-0f1a2b3c4d5e")!
        #expect(TipCardLinkRow.displayText(for: url) == "app.flipcash.com/tip/b0ced…")
    }

    @Test("The longest handle renders whole")
    func displayText_maximumLengthHandle_unclipped() {
        let url = URL(string: "https://app.flipcash.com/abcdefghijklmno")!
        #expect(TipCardLinkRow.displayText(for: url) == "app.flipcash.com/abcdefghijklmno")
    }

    @Test("A six-character handle renders whole")
    func displayText_shortHandle_unclipped() {
        let url = URL(string: "https://app.flipcash.com/taylor")!
        #expect(TipCardLinkRow.displayText(for: url) == "app.flipcash.com/taylor")
    }

    @Test("A non-handle segment at exactly the stub length is left alone")
    func displayText_nonHandleAtStubLength_unclipped() {
        let url = URL(string: "https://app.flipcash.com/a-bcd")!
        #expect(TipCardLinkRow.displayText(for: url) == "app.flipcash.com/a-bcd")
    }
}
