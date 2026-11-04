//
//  ChatSendBackStageTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import FlipcashCore
@testable import FlipcashUI

/// A Send Back row or footer appears without animating its bubble: the transcript applies those
/// cards' changes first, in place and with animation off, before the rest of the push.
@MainActor
@Suite("Chat Send Back stage")
struct ChatSendBackStageTests {

    private func cash(_ id: String, _ sendBack: ChatCashContent.SendBack?, sender: ChatMessage.Sender = .other) -> ChatItem {
        .message(ChatMessage(id: id, content: .cash(ChatCashContent(
            amount: "$5.00", token: "Cash",
            lines: .init(caption: "Noah Parker sent", counterpart: "to you"),
            sendBack: sendBack
        )), sender: sender))
    }

    private func text(_ id: String) -> ChatItem {
        .message(ChatMessage(id: id, text: "text-\(id)", sender: .me))
    }

    @Test("The status check resolving to Available stages the whole push, which reconfigures in place")
    func rowAppears_stagesWholePush() {
        let before = [cash("a", nil), text("b")]
        let after = [cash("a", .available), text("b")]
        #expect(ChatViewController.sendBackStage(from: before, to: after) == after)
    }

    @Test("A return arriving with the original's footer stages the footer alone, keeping the old rows")
    func footerWithArrival_stagesFooterOnly() {
        let before = [cash("a", nil, sender: .me)]
        let after = [cash("a", .sentBack, sender: .me), cash("r", nil)]
        #expect(ChatViewController.sendBackStage(from: before, to: after) == [cash("a", .sentBack, sender: .me)])
    }

    @Test("Sending turning to Sent Back, a resize, is staged")
    func sendingToSentBack_isStaged() {
        #expect(ChatViewController.sendBackStage(from: [cash("a", .sending)], to: [cash("a", .sentBack)]) != nil)
    }

    @Test("A push with no Send Back change stages nothing")
    func otherChange_stagesNothing() {
        let before = [cash("a", .available), text("b")]
        let after = [cash("a", .available), text("b"), text("c")]
        #expect(ChatViewController.sendBackStage(from: before, to: after) == nil)
    }
}
