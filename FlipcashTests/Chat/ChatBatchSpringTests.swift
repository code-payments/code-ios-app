//
//  ChatBatchSpringTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import DifferenceKit
import FlipcashCore
@testable import FlipcashUI

/// A batch update picks its spring from the diff: rows arriving or leaving ride the bouncy arrival
/// spring, and a diff that only reconfigures rows in place (a receipt moving, a status resolving)
/// glides on the non-bouncy reflow spring.
@MainActor
@Suite("Chat batch update spring")
struct ChatBatchSpringTests {

    private func message(
        _ id: String,
        sender: ChatMessage.Sender = .me,
        continuedByNext: Bool = false,
        continuationFromPrevious: Bool = false,
        receipt: ChatReceipt? = nil
    ) -> ChatItem {
        .message(ChatMessage(
            id: id,
            text: "text-\(id)",
            sender: sender,
            isContinuationFromPrevious: continuationFromPrevious,
            isContinuedByNext: continuedByNext,
            joinsBubbleAbove: continuationFromPrevious,
            joinsBubbleBelow: continuedByNext,
            receipt: receipt
        ))
    }

    private func spring(from before: [ChatItem], to after: [ChatItem]) -> ChatSpring {
        ChatViewController.batchSpring(for: StagedChangeset(source: before, target: after))
    }

    @Test("A send, which inserts a row, rides the arrival spring")
    func insert_ridesInsertion() {
        let before = [message("a", receipt: .delivered)]
        let after = [
            message("a", continuedByNext: true, receipt: .delivered),
            message("b", continuationFromPrevious: true),
        ]
        #expect(spring(from: before, to: after) == ChatMotion.insertion)
    }

    @Test("The typing dots giving way to a reply, a delete plus an insert, ride the arrival spring")
    func deleteAndInsert_ridesInsertion() {
        let before = [message("a"), .typingIndicator(typists: [])]
        let after = [message("a"), message("b", sender: .other)]
        #expect(spring(from: before, to: after) == ChatMotion.insertion)
    }

    @Test("A row leaving on its own rides the arrival spring")
    func delete_ridesInsertion() {
        let before = [message("a"), message("b")]
        let after = [message("a")]
        #expect(spring(from: before, to: after) == ChatMotion.insertion)
    }

    @Test("The receipt handoff, updates only, rides the reflow spring")
    func receiptHandoff_ridesReflow() {
        let before = [
            message("a", continuedByNext: true, receipt: .delivered),
            message("b", continuationFromPrevious: true),
        ]
        let after = [
            message("a", continuedByNext: true),
            message("b", continuationFromPrevious: true, receipt: .delivered),
        ]
        #expect(spring(from: before, to: after) == ChatMotion.reflow)
    }

    @Test("Delivered swapping to Read in place rides the reflow spring")
    func readSwap_ridesReflow() {
        let before = [message("a", receipt: .delivered)]
        let after = [message("a", receipt: .read(time: "3:42 PM"))]
        #expect(spring(from: before, to: after) == ChatMotion.reflow)
    }
}
