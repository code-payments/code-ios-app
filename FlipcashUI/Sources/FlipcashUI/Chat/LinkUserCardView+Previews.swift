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
        blurHash: String? = Self.blurHash
    ) -> LinkCard.User.State {
        .resolved(LinkCard.User.Resolved(
            userID: userID,
            isOwn: isOwn,
            displayName: displayName,
            handle: handle,
            joined: joined,
            imageData: nil,
            blurHash: blurHash
        ))
    }

    /// Every state, labelled, in the order the PR describes them, with the handle the link names.
    static let all: [(name: String, state: LinkCard.User.State, linkedHandle: String?)] = [
        ("Someone else", resolved(), "@satoshi"),
        ("No handle (UUID link)", resolved(handle: nil), nil),
        ("No picture", resolved(blurHash: nil), "@satoshi"),
        ("No join date", resolved(joined: nil), "@satoshi"),
        ("Your own link", resolved(isOwn: true), "@satoshi"),
        ("Not found", .notFound, "@nobodyhere"),
        ("Not found (UUID link)", .notFound, nil),
    ]

    /// Long and unusual data, to show where the card wraps and where it ends in an ellipsis.
    static let stress: [(name: String, state: LinkCard.User.State, linkedHandle: String?)] = [
        ("Short", resolved(displayName: "Al", handle: "@al", joined: "Joined May 2024"), "@al"),
        (
            "64-scalar name, longest handle and joined line",
            resolved(
                displayName: "Maximilian Alexander Constantine Bartholomew von Hohenzollern-Sig",
                handle: "@abcdefghijklmno",
                joined: "Joined September 2026"
            ),
            "@abcdefghijklmno"
        ),
        (
            "64-scalar name, one word",
            resolved(displayName: "Supercalifragilisticexpialidociousandthensomemorelettersuntilsixt"),
            "@satoshi"
        ),
        ("Emoji", resolved(displayName: String(repeating: "👩‍👩‍👧‍👦", count: 9)), "@satoshi"),
        ("CJK", resolved(displayName: "山田太郎の非常に長い表示名テストです日本語の名前"), "@satoshi"),
        ("Arabic", resolved(displayName: "محمد عبد الرحمن بن عبد العزيز آل سعود"), "@satoshi"),
    ]

    /// The width the transcript gives a card on a 390pt-wide phone.
    static let cardWidth: CGFloat = LinkGroupCardSamples.cardWidth

    /// A card drawn the way the bubble draws it: as wide as its content, at most the card width.
    static func card(_ state: LinkCard.User.State, linkedHandle: String?) -> some View {
        LinkUserCardContent(state: state, linkedHandle: linkedHandle)
            .frame(width: cardWidth)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `samples`, labelled, in a scrolling column, with the loading shimmer last when asked for.
    static func gallery(
        _ samples: [(name: String, state: LinkCard.User.State, linkedHandle: String?)] = all,
        showsLoading: Bool = true
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(samples, id: \.name) { sample in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sample.name).font(.caption).foregroundStyle(Color.textSecondary)
                        card(sample.state, linkedHandle: sample.linkedHandle)
                    }
                }
                if showsLoading {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Loading").font(.caption).foregroundStyle(Color.textSecondary)
                        LinkCardShimmerSample()
                            .frame(
                                width: LinkUserCardContent.Layout.shimmerWidth,
                                height: LinkUserCardContent.Layout.shimmerHeight
                            )
                    }
                }
            }
            .padding(24)
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

/// The loading state as the card draws it: the link cards' shimmer, at the card's own size and
/// corner.
private struct LinkCardShimmerSample: UIViewRepresentable {
    func makeUIView(context: Context) -> LinkCardShimmerView {
        let view = LinkCardShimmerView(
            ground: UIColor(Color.backgroundRow),
            highlight: UIColor.white.withAlphaComponent(0.06)
        )
        view.layer.cornerRadius = GroupCardView.Layout.radius
        view.layer.cornerCurve = .continuous
        view.setShimmering(true)
        return view
    }

    func updateUIView(_ view: LinkCardShimmerView, context: Context) {}
}

#Preview("Person card states") {
    LinkUserCardSamples.gallery()
}

#Preview("Person card, long data") {
    LinkUserCardSamples.gallery(LinkUserCardSamples.stress, showsLoading: false)
}

#Preview("Person card, accessibility sizes") {
    LinkUserCardSamples.gallery(
        Array(LinkUserCardSamples.all.prefix(1) + LinkUserCardSamples.stress.prefix(2)) + [LinkUserCardSamples.all[5]],
        showsLoading: false
    )
    .environment(\.dynamicTypeSize, .accessibility3)
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
