//
//  ChatCashCardSizingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import ChatLayout
import FlipcashCore
@testable import FlipcashUI

/// Every chat row self-sizes to its own content: text and date rows to their text, and the cash
/// card to its fixed-height card plus the inline receipt line below it. `ChatViewController`
/// overrides no per-row sizes, so each reports ChatLayout's `.auto` default.
@MainActor
@Suite("Every chat row self-sizes (.auto)")
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

    @Test("A cash row self-sizes (.auto) like every other row")
    func cashRow_isAuto() {
        let items: [ChatItem] = [
            .message(ChatMessage(id: "1", text: "hi", sender: .me)),
            cashRow("2", .other),
        ]
        #expect(sized(items, at: 1) == .auto)
    }

    @Test("Date separator, text, and receipt-carrying rows self-size (.auto)")
    func otherRows_areAuto() {
        let items: [ChatItem] = [
            .profileCard(ChatProfileCard(
                name: "Ted Livingston",
                avatarID: "ted",
                imageData: nil,
                counterpart: .contact(phone: "519 802-3885")
            )),
            .dateSeparator(id: "sep", text: "Today 1:00 PM"),
            .message(ChatMessage(id: "1", text: "hello", sender: .other)),
            .message(ChatMessage(id: "2", text: "sent", sender: .me, receipt: "Delivered")),
        ]
        for index in items.indices {
            #expect(sized(items, at: index) == .auto, "row \(index) should self-size")
        }
    }
}
