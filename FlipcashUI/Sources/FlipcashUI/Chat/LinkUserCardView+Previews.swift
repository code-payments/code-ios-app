//
//  LinkUserCardView+Previews.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit) && DEBUG
import UIKit
import SwiftUI
import FlipcashCore

/// Sample person cards, one per state the card draws, for previews and the review screenshots.
enum LinkUserCardSamples {

    static let blurHash = "LGF5]+Yk^6#M@-5c,1J5@[or[Q6."
    static let userID = UUID(uuidString: "2b0b4d1e-9f3e-4c21-9f1a-6d5f7c8e9a0b")!

    static func resolved(
        isOwn: Bool = false,
        displayName: String = "Satoshi Nakamoto",
        handle: String? = "@satoshi",
        joined: String? = "Joined March 2024",
        fee: String? = "Minimum To Chat: $1.00",
        blurHash: String? = Self.blurHash
    ) -> LinkCard.User.State {
        .resolved(LinkCard.User.Resolved(
            userID: userID,
            isOwn: isOwn,
            displayName: displayName,
            handle: handle,
            joined: joined,
            fee: fee,
            imageData: nil,
            blurHash: blurHash
        ))
    }

    /// Every state, labelled, in the order the PR describes them, with the handle the link names.
    static let all: [(name: String, state: LinkCard.User.State, linkedHandle: String?)] = [
        ("Someone else, with a fee", resolved(), "@satoshi"),
        ("Someone else, no fee", resolved(fee: nil), "@satoshi"),
        ("No handle (UUID link)", resolved(handle: nil), nil),
        ("No picture", resolved(blurHash: nil), "@satoshi"),
        ("No join date", resolved(joined: nil), "@satoshi"),
        ("Your own link", resolved(isOwn: true, fee: nil), "@satoshi"),
        ("Not found", .notFound, "@nobodyhere"),
        ("Not found (UUID link)", .notFound, nil),
    ]

    /// The width the transcript gives a card on a 390pt-wide phone.
    static let cardWidth: CGFloat = LinkGroupCardSamples.cardWidth

    /// A card drawn the way the bubble draws it: full card width, growing with its content.
    static func card(_ state: LinkCard.User.State, linkedHandle: String?) -> some View {
        LinkUserCardContent(state: state, linkedHandle: linkedHandle, width: cardWidth)
            .frame(width: cardWidth)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Every state, labelled, in a scrolling column.
    static func gallery() -> some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(all, id: \.name) { sample in
                    VStack(spacing: 6) {
                        Text(sample.name).font(.caption).foregroundStyle(Color.textSecondary)
                        card(sample.state, linkedHandle: sample.linkedHandle)
                    }
                }
                VStack(spacing: 6) {
                    Text("Loading").font(.caption).foregroundStyle(Color.textSecondary)
                    LinkCardShimmerSample()
                        .frame(width: cardWidth, height: cardWidth * TipcardProportions.aspectRatio)
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.backgroundMain)
    }

    // MARK: - Transcript -

    static let userURL = URL(string: "https://flipcash.com/satoshi")!

    /// Answers every card at once, from a fixed table.
    final class Source: LinkCardSource {
        let states: [URL: LinkCard.State]

        init(user: LinkCard.User.State) {
            let group = LinkGroupCardSamples.Source(group: LinkGroupCardSamples.resolved())
            var states = group.states
            states[userURL] = .user(user)
            self.states = states
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

    /// A person link on its own, then the group card's split message and cash link, so the three
    /// cards' widths can be compared.
    static func transcript() -> [ChatItem] {
        let userText = userURL.absoluteString
        let userRange = NSRange(location: 0, length: (userText as NSString).length)
        let userCard = LinkCard.user(LinkCard.User(
            url: userURL,
            identity: .username(Username("satoshi")!),
            range: userRange
        ))
        let person = ChatItem.message(ChatMessage(
            id: "user",
            text: userText,
            sender: .other,
            linkPreview: LinkPreview(links: [DetectedLink(range: userRange, url: userURL)], card: userCard)
        ))
        return [person] + LinkGroupCardSamples.transcript()
    }

    /// Holds the transcript previews' sources, which the controller only references weakly.
    @MainActor static var retained: [Source] = []

    @MainActor static func transcriptController(
        user: LinkCard.User.State,
        contentSize: UIContentSizeCategory = .large
    ) -> ChatViewController {
        let source = Source(user: user)
        retained.append(source)
        let controller = ChatViewController()
        controller.traitOverrides.preferredContentSizeCategory = contentSize
        controller.linkCardSource = source
        controller.update(items: transcript())
        return controller
    }
}

/// The loading state as the card draws it: the link cards' shimmer, at the card's own proportion
/// and corner.
private struct LinkCardShimmerSample: UIViewRepresentable {
    func makeUIView(context: Context) -> LinkCardShimmerView {
        let view = LinkCardShimmerView(
            ground: UIColor(Color.backgroundRow),
            highlight: UIColor.white.withAlphaComponent(0.06)
        )
        view.layer.cornerRadius = LinkUserCardSamples.cardWidth * TipcardProportions.cornerRadiusFraction
        view.layer.cornerCurve = .continuous
        view.setShimmering(true)
        return view
    }

    func updateUIView(_ view: LinkCardShimmerView, context: Context) {}
}

#Preview("Person card states") {
    LinkUserCardSamples.gallery()
}

#Preview("Person card, accessibility XL") {
    ScrollView {
        LinkUserCardSamples.card(LinkUserCardSamples.resolved(), linkedHandle: "@satoshi")
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
    }
    .background(Color.backgroundMain)
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Beside a group card and a cash card") {
    LinkUserCardSamples.transcriptController(user: LinkUserCardSamples.resolved())
}

#Preview("Beside other cards, accessibility XL") {
    LinkUserCardSamples.transcriptController(
        user: LinkUserCardSamples.resolved(),
        contentSize: .accessibilityExtraLarge
    )
}
#endif
