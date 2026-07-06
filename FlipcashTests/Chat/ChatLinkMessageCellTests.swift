import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatLinkMessageCell")
struct ChatLinkMessageCellTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    private func makeCell() -> ChatLinkMessageCell {
        let cell = ChatLinkMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        cell.cache = LinkMetadataCache(fetcher: FailingFetcher()) // no network; card stays empty
        return cell
    }

    @Test("A URL-only message hides the text bubble; the lift targets the card")
    func urlOnly_hidesBubble() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://apple.com", sender: .me,
                              linkPreview: LinkPreview(url: url("https://apple.com"), bubbleText: "")),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isHidden == true)
        #expect(cell.liftPreviewView is LinkableBubbleView == false)
    }

    @Test("A text+URL message shows the bubble; the lift targets the bubble")
    func textAndURL_showsBubble() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "see https://apple.com", sender: .other,
                              linkPreview: LinkPreview(url: url("https://apple.com"), bubbleText: "see")),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isHidden == false)
        #expect(cell.liftPreviewView is LinkableBubbleView == true)
    }

    @Test("A failed link message disables the card's own tap so retry wins")
    func failedMessage_disablesCardTap() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://apple.com", sender: .me,
                              isFailed: true,
                              linkPreview: LinkPreview(url: url("https://apple.com"), bubbleText: "")),
            maxWidth: 250
        )
        let card = cell.liftPreviewView
        let cardTap = card.gestureRecognizers?.first { $0 is UITapGestureRecognizer }
        #expect(cardTap?.isEnabled == false)
    }

    @Test("A failed link message also disables the bubble's own link taps so retry wins")
    func failedMessage_disablesBubbleInteraction() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://a.com then https://b.com", sender: .me,
                              isFailed: true,
                              linkPreview: LinkPreview(url: url("https://b.com"), bubbleText: "https://a.com then")),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isUserInteractionEnabled == false)
    }

    @Test("A non-failed link message keeps the bubble's link taps enabled")
    func nonFailedMessage_keepsBubbleInteractionEnabled() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://a.com then https://b.com", sender: .me,
                              linkPreview: LinkPreview(url: url("https://b.com"), bubbleText: "https://a.com then")),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isUserInteractionEnabled == true)
    }

    @Test("The card shows the domain immediately, before metadata resolves")
    func configure_showsDomainImmediately() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://apple.com", sender: .me,
                              linkPreview: LinkPreview(url: url("https://apple.com"), bubbleText: "")),
            maxWidth: 250
        )
        let texts = cell.liftPreviewView.descendants(of: UILabel.self).compactMap(\.text)
        #expect(texts.contains("apple.com"))
    }
}

/// A fetcher that always fails, so tests exercise visibility without touching the network.
private struct FailingFetcher: LinkMetadataFetching {
    func fetch(_ url: URL) async throws -> SendableLinkMetadata { throw URLError(.cancelled) }
}
