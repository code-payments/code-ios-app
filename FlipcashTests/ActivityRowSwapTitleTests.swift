//
//  ActivityRowSwapTitleTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash

@Suite("Swap row title")
struct ActivityRowSwapTitleTests {

    @Test("Both resolved token names render as the conversion pair")
    func bothNamesRender() {
        #expect(ActivityRow.swapTitle(from: "Dollars", to: "Jeffy") == "Dollars → Jeffy")
    }

    @Test("An unresolved leg falls back to the server-rendered title")
    func unresolvedLegFallsBack() {
        #expect(ActivityRow.swapTitle(from: nil, to: "Jeffy") == nil)
        #expect(ActivityRow.swapTitle(from: "Dollars", to: nil) == nil)
        #expect(ActivityRow.swapTitle(from: "", to: "Jeffy") == nil)
        #expect(ActivityRow.swapTitle(from: "Dollars", to: "") == nil)
    }
}
