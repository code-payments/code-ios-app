import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatLinkMessageCell")
struct ChatLinkMessageCellTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    private func makeCell() -> ChatLinkMessageCell {
        ChatLinkMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
    }

    @Test("A failed link message disables the bubble's own link taps so retry wins")
    func failedMessage_disablesBubbleInteraction() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://apple.com", sender: .me,
                              isFailed: true,
                              linkPreview: LinkPreview(url: url("https://apple.com"))),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isUserInteractionEnabled == false)
    }

    @Test("A non-failed link message keeps the bubble's link taps enabled")
    func nonFailedMessage_keepsBubbleInteractionEnabled() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://apple.com", sender: .me,
                              linkPreview: LinkPreview(url: url("https://apple.com"))),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isUserInteractionEnabled == true)
    }
}
