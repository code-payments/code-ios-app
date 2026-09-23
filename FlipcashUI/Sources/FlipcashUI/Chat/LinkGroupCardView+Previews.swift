//
//  LinkGroupCardView+Previews.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit) && DEBUG
import UIKit
import SwiftUI
import FlipcashCore

/// Sample group cards, one per state the card draws, for previews and the review screenshots.
enum LinkGroupCardSamples {

    static let blurHash = "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."

    static func resolved(
        requirement: String? = "Balance Requirement:\n$100 of $BadBoys",
        blurHash: String? = Self.blurHash,
        title: String = "Ballers"
    ) -> LinkCard.Group.State {
        .resolved(LinkCard.Group.Resolved(
            title: title,
            memberCount: "128 people",
            avatarID: "preview-group",
            imageData: nil,
            blurHash: blurHash,
            requirement: requirement
        ))
    }

    /// Every state, labelled, in the order the PR describes them.
    static let all: [(name: String, state: LinkCard.Group.State)] = [
        ("No requirement", resolved(requirement: nil)),
        ("Token requirement", resolved()),
        ("Unavailable", .unavailable),
        ("No picture", resolved(requirement: "Balance Requirement:\n$25", blurHash: nil)),
    ]

    /// The width the transcript gives a card on a 390pt-wide phone.
    static let cardWidth: CGFloat = 264

    /// A card drawn the way the bubble draws it: full card width, the link cards' ratio as its
    /// least height, growing past it with its content.
    static func card(_ state: LinkCard.Group.State) -> some View {
        LinkGroupCardContent(state: state)
            .frame(width: cardWidth)
            .frame(minHeight: cardWidth * 224 / 328)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Transcript -

    static let groupURL = URL(string: "https://app.flipcash.com/chat/6f1c3a9e-2b7d-4e0a-9c55-1d2e3f405162")!
    static let cashURL = URL(string: "https://app.flipcash.com/c#e=preview")!

    /// Answers every card at once, from a fixed table.
    final class Source: LinkCardSource {
        let states: [URL: LinkCard.State]

        init(group: LinkCard.Group.State) {
            states = [
                groupURL: .group(group),
                cashURL: .cash(.resolved(LinkCard.Cash.Resolved(
                    amount: "$15.00",
                    claim: .claimable,
                    tokenName: "USD",
                    iconURL: nil
                ))),
            ]
        }

        func known(_ card: LinkCard) -> LinkCard.State? { states[card.url] }

        func states(for card: LinkCard) -> AsyncStream<LinkCard.State> {
            let state = states[card.url]
            return AsyncStream { continuation in
                if let state { continuation.yield(state) }
                continuation.finish()
            }
        }
    }

    /// A message that says something either side of a group link, split into its three rows, next
    /// to a cash link sent on its own, so the two cards' widths can be compared.
    static func transcript() -> [ChatItem] {
        let groupText = "\(groupURL.absoluteString)"
        let groupID = ConversationID(uuidString: "6f1c3a9e-2b7d-4e0a-9c55-1d2e3f405162")!
        let whole = "Come hang out in here \(groupText) we're talking about the drop"
        let range = NSRange(location: 0, length: (groupText as NSString).length)
        let groupCard = LinkCard.group(LinkCard.Group(url: groupURL, chatID: groupID, range: range))

        let cashText = cashURL.absoluteString
        let cashRange = NSRange(location: 0, length: (cashText as NSString).length)
        let cashCard = LinkCard.cash(LinkCard.Cash(url: cashURL, entropy: "preview", range: cashRange))

        func part(_ kind: ChatMessagePart.Kind) -> ChatMessagePart {
            ChatMessagePart(messageID: "split", kind: kind, messageText: whole)
        }

        return [
            .message(ChatMessage(
                id: part(.leadingText).rowID,
                text: "Come hang out in here",
                sender: .other,
                isContinuedByNext: true,
                part: part(.leadingText)
            )),
            .message(ChatMessage(
                id: part(.card).rowID,
                text: groupText,
                sender: .other,
                isContinuationFromPrevious: true,
                isContinuedByNext: true,
                linkPreview: LinkPreview(links: [DetectedLink(range: range, url: groupURL)], card: groupCard),
                part: part(.card)
            )),
            .message(ChatMessage(
                id: part(.trailingText).rowID,
                text: "we're talking about the drop",
                sender: .other,
                isContinuationFromPrevious: true,
                part: part(.trailingText)
            )),
            .message(ChatMessage(
                id: "cash",
                text: cashText,
                sender: .me,
                receipt: .delivered,
                linkPreview: LinkPreview(links: [DetectedLink(range: cashRange, url: cashURL)], card: cashCard)
            )),
        ]
    }

    /// Holds the transcript previews' sources, which the controller only references weakly.
    @MainActor static var retained: [Source] = []

    @MainActor static func transcriptController(
        group: LinkCard.Group.State,
        contentSize: UIContentSizeCategory = .large
    ) -> ChatViewController {
        let source = Source(group: group)
        retained.append(source)
        let controller = ChatViewController()
        controller.traitOverrides.preferredContentSizeCategory = contentSize
        controller.linkCardSource = source
        controller.update(items: transcript())
        return controller
    }
}

#Preview("Group card states") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(LinkGroupCardSamples.all, id: \.name) { sample in
                VStack(spacing: 6) {
                    Text(sample.name).font(.caption).foregroundStyle(Color.textSecondary)
                    LinkGroupCardSamples.card(sample.state)
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
    .background(Color.backgroundMain)
}

#Preview("Group card, accessibility XL") {
    ScrollView {
        LinkGroupCardSamples.card(LinkGroupCardSamples.resolved())
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
    }
    .background(Color.backgroundMain)
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Split message beside a cash card") {
    LinkGroupCardSamples.transcriptController(group: LinkGroupCardSamples.resolved())
}

#Preview("Split message, accessibility XL") {
    LinkGroupCardSamples.transcriptController(
        group: LinkGroupCardSamples.resolved(),
        contentSize: .accessibilityExtraLarge
    )
}
#endif
