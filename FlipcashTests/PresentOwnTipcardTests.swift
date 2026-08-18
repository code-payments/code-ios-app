//
//  PresentOwnTipcardTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Session.presentOwnTipcard")
struct PresentOwnTipcardTests {

    private func makeSession() throws -> Session {
        try SessionContainer.makeTest(holdings: []).session
    }

    @Test("presents the tipcard bill with a pop and marks a bill showing")
    func present_setsTipcardBill() throws {
        let session = try makeSession()
        let code = Data([1, 2, 3])

        session.presentOwnTipcard(codeData: code, name: "Ada", avatar: nil)

        #expect(session.billState.bill == .tipcard(codeData: code, name: "Ada", avatar: nil))
        #expect(session.presentationState == .visible(.pop))
        #expect(session.isShowingBill)
    }

    @Test("is a no-op while a bill is already showing")
    func present_whileShowing_isNoop() throws {
        let session = try makeSession()
        let first = Data([1])
        session.presentOwnTipcard(codeData: first, name: "Ada", avatar: nil)

        session.presentOwnTipcard(codeData: Data([9]), name: "Grace", avatar: nil)

        #expect(session.billState.bill == .tipcard(codeData: first, name: "Ada", avatar: nil))
    }

    @Test("dismissing clears the bill")
    func dismiss_clearsBill() throws {
        let session = try makeSession()
        session.presentOwnTipcard(codeData: Data([1]), name: "Ada", avatar: nil)

        session.dismissCashBill(style: .slide)

        #expect(session.billState.bill == nil)
        #expect(!session.isShowingBill)
    }
}
