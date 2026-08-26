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

    private let handle = Username("taylor")!

    @Test("An unclaimed handle is informational and names the handle")
    func unclaimedHandle_infoNamingTheHandle() {
        let item = TipFlow.failureDialog(for: ErrorResolve.notFound, handle: handle)
        #expect(item.style == .standard)
        #expect(item.title == "No Such Account")
        #expect(item.subtitle == "Nobody has claimed @taylor")
    }

    @Test("A profile the server didn't stamp with an id reads the same as a miss")
    func idlessProfile_readsAsUnclaimed() {
        // `fetchProfile` answers an unclaimed handle with `Profile.empty`, so the
        // flow's own error stands in for the server's `.notFound` on that half.
        let item = TipFlow.failureDialog(for: ErrorFetchProfile.notFound, handle: handle)
        #expect(item.title == "No Such Account")
    }

    @Test("A network failure on a handle apologises instead of blaming the link")
    func transportFailure_genericError() {
        let item = TipFlow.failureDialog(for: ErrorResolve.transportFailure, handle: handle)
        #expect(item.style == .destructive)
        #expect(item.title == "Couldn't Open Tip Card")
        #expect(item.subtitle == "Please check your connection and try again")
    }

    @Test("A scanned code never claims nobody holds it")
    func scannedCode_neverSaysUnclaimed() {
        // There is no handle to name, and a miss on an id is a fetch that didn't
        // land rather than a wrong address.
        let item = TipFlow.failureDialog(for: ErrorResolve.notFound, handle: nil)
        #expect(item.style == .destructive)
        #expect(item.title == "Couldn't Open Tip Card")
    }
}
