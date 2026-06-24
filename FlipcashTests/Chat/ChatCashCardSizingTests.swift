//
//  ChatCashCardSizingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import ChatLayout
@testable import FlipcashUI

/// The cash card is a fixed-size row, so `ChatViewController` reports an exact height for it. That
/// makes an inserted cash cell lay out at its real 170pt height immediately, instead of being placed
/// at ChatLayout's small estimate and depending on a follow-up self-size pass — a pass iOS 26 skips
/// during the animated batch update, which left the card clipped to the estimate (invisible) until
/// the chat was reopened. Text/date/receipt rows keep self-sizing.
@MainActor
@Suite("Cash rows report an exact height; other rows self-size")
struct ChatCashCardSizingTests {

    private func sized(_ items: [ChatItem], at index: Int) -> ItemSize {
        let controller = ChatViewController()
        controller.update(items: items)
        let layout = controller.collectionViewLayout as! CollectionViewChatLayout
        return controller.sizeForItem(layout, at: IndexPath(item: index, section: 0))
    }

    private func cashRow(_ id: String, _ sender: ChatMessage.Sender) -> ChatItem {
        .message(ChatMessage(
            id: id,
            content: .cash(ChatCashContent(amount: "$0.01", token: "Launch It", flagImageName: "ca")),
            sender: sender
        ))
    }

    @Test("A cash row reports an exact height equal to the card height")
    func cashRow_isExactCardHeight() {
        let items: [ChatItem] = [
            .message(ChatMessage(id: "1", text: "hi", sender: .me)),
            cashRow("2", .other),
        ]
        guard case .exact(let size) = sized(items, at: 1) else {
            Issue.record("expected the cash row to report an exact size")
            return
        }
        #expect(size.height == ChatCashCardCell.cardSize.height)
    }

    @Test("Text, date separator, and receipt-bearing rows keep self-sizing (.auto)")
    func nonCashRows_areAuto() {
        let items: [ChatItem] = [
            .dateSeparator(id: "sep", text: "Today 1:00 PM"),
            .message(ChatMessage(id: "1", text: "hello", sender: .other)),
            .message(ChatMessage(id: "r", text: "ok", sender: .me, receipt: "Delivered")),
        ]
        for index in items.indices {
            #expect(sized(items, at: index) == .auto, "row \(index) should self-size")
        }
    }
}
