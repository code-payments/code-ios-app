//
//  TipFlowFailureDialogTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Tip resolve failure copy")
struct TipFlowFailureDialogTests {

    @Test("A failed resolve apologises instead of blaming the code")
    func failedResolve_genericError() {
        let item = TipFlow.failureDialog
        #expect(item.style == .destructive)
        #expect(item.title == "Couldn't Open Profile Card")
        #expect(item.subtitle == "Please check your connection and try again")
    }
}
