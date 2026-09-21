//
//  ChatAuthorAvatarPlacementTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@Suite("The author's face in a group transcript")
@MainActor
struct ChatAuthorAvatarPlacementTests {

    private let author = ChatAuthor(id: UserID(), name: "Kt")

    private func cell(for message: ChatMessage) -> ChatMessageCell {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        cell.configure(with: message, maxWidth: 250)
        cell.layoutIfNeeded()
        return cell
    }

    private func message(continuationFromPrevious: Bool, continuedByNext: Bool) -> ChatMessage {
        ChatMessage(
            id: "1",
            text: "hi there",
            sender: .other,
            isContinuationFromPrevious: continuationFromPrevious,
            isContinuedByNext: continuedByNext,
            author: author,
            isAttributedTranscript: true
        )
    }

    private func avatar(in cell: ChatColumnCell) -> ChatAuthorAvatarView? {
        cell.contentView.subviews.compactMap { $0 as? ChatAuthorAvatarView }.first
    }

    @Test("The row that opens a run draws it")
    func firstRowOfRun_drawsTheFace() {
        let cell = self.cell(for: message(continuationFromPrevious: false, continuedByNext: true))
        #expect(avatar(in: cell)?.isHidden == false)
    }

    @Test("The row that closes a run does not")
    func lastRowOfRun_drawsNoFace() {
        let cell = self.cell(for: message(continuationFromPrevious: true, continuedByNext: false))
        #expect(avatar(in: cell)?.isHidden == true)
    }

    @Test("A single-row run draws it, having no other row to")
    func loneRow_drawsTheFace() {
        let cell = self.cell(for: message(continuationFromPrevious: false, continuedByNext: false))
        #expect(avatar(in: cell)?.isHidden == false)
    }

    @Test("It lines up with the top of the bubble, below the name")
    func face_alignsWithTheBubbleTop() throws {
        let cell = self.cell(for: message(continuationFromPrevious: false, continuedByNext: true))
        let face = try #require(avatar(in: cell))
        let bubble = cell.bubbleView.convert(cell.bubbleView.bounds, to: cell.contentView)
        #expect(abs(face.frame.minY - bubble.minY) < 0.5)
        // The name opens the run above both, so the face cannot be at the row's very top.
        #expect(face.frame.minY > 0)
    }
}
