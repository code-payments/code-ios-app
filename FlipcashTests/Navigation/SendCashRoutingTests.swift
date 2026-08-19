//
//  SendCashRoutingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Send Cash routing")
@MainActor
struct SendCashRoutingTests {

    private static let target: SendTarget = .tip(
        TipRecipient(userID: UUID(), displayName: "Fred", origin: .chat)
    )

    @Test("The sendAmount sheet maps to the sendAmount stack")
    func sendAmountSheet_mapsToSendAmountStack() {
        #expect(AppRouter.SheetPresentation.sendAmount(Self.target).stack == .sendAmount)
    }

    // Regression: a chat opened from the Chat tab lives inside the tab's nav
    // stack with no sheet presented. Send Cash must still open — presenting the
    // amount sheet at root — rather than no-op the way a bare `presentNested`
    // does on an empty stack.
    @Test("With no sheet presented, Send Cash presents at root")
    func fromTabChat_presentsAtRoot() {
        let router = AppRouter()
        router.activeTabStack = .tips
        router.presentSendAmount(Self.target)
        #expect(router.presentedSheets == [.sendAmount(Self.target)])
    }

    // A chat opened as a sheet (the scanner's tips flow) keeps the old
    // behaviour: the amount sheet stacks on top so dismissing reveals the chat.
    @Test("Over a presented chat sheet, Send Cash stacks nested")
    func overChatSheet_stacksNested() {
        let router = AppRouter()
        router.present(.tips)
        router.presentSendAmount(Self.target)
        #expect(router.presentedSheets == [.tips, .sendAmount(Self.target)])
    }
}
