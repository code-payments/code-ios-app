//
//  Regression_6ae1d311c6c10d79fa57232c.swift
//  FlipcashTests
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// A reconfigure dequeued `ChatMessageCell` over a live `ChatLinkMessageCell` ("Dequeued reuse
/// identifier: ChatMessageCell; Original reuse identifier: ChatLinkMessageCell") while earlier
/// batches were still animating. None of these reproduce it: they pin the paths ruled out so far
/// (overlapping batches, cards growing mid-animation, a scrolled transcript) rather than guard a
/// fix. Each test pushes without settling, so the next batch lands on the previous one's
/// animation. Window-attached and serialized because a regression here aborts the runner.
@MainActor
@Suite("Regression: 6ae1d31 – reconfigure over an animating link cell", .serialized, .bug("6ae1d311c6c10d79fa57232c"))
struct Regression_6ae1d311c6c10d79fa57232c {

    /// The window keeps the controller's view attached for the test's lifetime; dropping it would
    /// silently reroute `update` onto the off-window `reloadData` path.
    private struct WindowedTranscript {
        let window: UIWindow
        let controller: ChatViewController
    }

    private func windowedTranscript(seed: [ChatItem]) async -> WindowedTranscript {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: seed)
        await settle(controller)
        return WindowedTranscript(window: window, controller: controller)
    }

    private func settle(_ controller: ChatViewController) async {
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private func history(_ count: Int) -> [ChatItem] {
        (0..<count).map {
            .message(ChatMessage(id: "h\($0)", text: "history \($0)", sender: $0.isMultiple(of: 2) ? .me : .other))
        }
    }

    private func text(_ id: String, _ text: String, link: Bool, receipt: ChatReceipt? = nil) -> ChatItem {
        .message(ChatMessage(
            id: id,
            text: text,
            sender: .other,
            receipt: receipt,
            linkPreview: link ? LinkPreview(url: URL(string: "https://example.com/\(id)")!) : nil
        ))
    }

    /// Every visible cell's class matches the row it sits on.
    private func expectLiveClassesMatch(_ controller: ChatViewController, _ items: [ChatItem]) {
        for indexPath in controller.collectionView.indexPathsForVisibleItems {
            guard let cell = controller.collectionView.cellForItem(at: indexPath) else { continue }
            #expect(cell.reuseIdentifier == items[indexPath.item].cellReuseIdentifier, "row \(indexPath.item)")
        }
    }

    @Test("A link lost, then the same row edited before the first batch lands")
    func linkLost_thenEdited_backToBack() async {
        let base = history(30)
        let transcript = await windowedTranscript(seed: base + [text("x", "see https://example.com/x", link: true)])

        transcript.controller.update(items: base + [text("x", "see https://example.com/x", link: false)])
        let final = base + [text("x", "see https://example.com/x (edited)", link: false)]
        transcript.controller.update(items: final)
        await settle(transcript.controller)

        expectLiveClassesMatch(transcript.controller, final)
    }

    @Test("A link gained, then the same row edited before the first batch lands")
    func linkGained_thenEdited_backToBack() async {
        let base = history(30)
        let transcript = await windowedTranscript(seed: base + [text("x", "see https://example.com/x", link: false)])

        transcript.controller.update(items: base + [text("x", "see https://example.com/x", link: true)])
        let final = base + [text("x", "see https://example.com/x", link: true, receipt: .delivered)]
        transcript.controller.update(items: final)
        await settle(transcript.controller)

        expectLiveClassesMatch(transcript.controller, final)
    }

    @Test("A link lost above an arrival, then a row below reconfigures before the first batch lands")
    func linkLostWithArrival_thenNeighbourReconfigured_backToBack() async {
        let base = history(30)
        let transcript = await windowedTranscript(seed: base + [
            text("x", "see https://example.com/x", link: true),
            text("y", "plain", link: false),
        ])

        transcript.controller.update(items: base + [
            text("x", "see https://example.com/x", link: false),
            text("y", "plain", link: false),
            text("z", "arrival", link: true),
        ])
        let final = base + [
            text("x", "see https://example.com/x", link: false, receipt: .delivered),
            text("y", "plain", link: false, receipt: .delivered),
            text("z", "arrival", link: true, receipt: .delivered),
        ]
        transcript.controller.update(items: final)
        await settle(transcript.controller)

        expectLiveClassesMatch(transcript.controller, final)
    }

    @Test("Three pushes flip a link row's class and back before any batch lands")
    func linkFlipsTwice_thenEdited_backToBack() async {
        let base = history(30)
        let transcript = await windowedTranscript(seed: base + [text("x", "see https://example.com/x", link: true)])

        transcript.controller.update(items: base + [text("x", "see https://example.com/x", link: false)])
        transcript.controller.update(items: base + [text("x", "see https://example.com/x", link: true)])
        let final = base + [text("x", "see https://example.com/x", link: true, receipt: .delivered)]
        transcript.controller.update(items: final)
        await settle(transcript.controller)

        expectLiveClassesMatch(transcript.controller, final)
    }

    // MARK: - Cards that resize mid-animation, on a scrolled transcript

    /// Hands every subscriber its own stream and lets the test answer them all at once, so a
    /// card's lookup lands exactly when the test wants it to: mid-animation.
    private final class Source: LinkCardSource {
        private var continuations: [LinkCard: [AsyncStream<LinkCard.State>.Continuation]] = [:]

        func known(_ card: LinkCard) -> LinkCard.State? { nil }

        func states(for card: LinkCard) -> AsyncStream<LinkCard.State> {
            let (stream, continuation) = AsyncStream<LinkCard.State>.makeStream()
            continuations[card, default: []].append(continuation)
            return stream
        }

        func answer(_ card: LinkCard, _ state: LinkCard.State) {
            continuations[card]?.forEach { $0.yield(state) }
        }
    }

    private static func groupCard(_ byte: UInt8) -> LinkCard {
        .group(LinkCard.Group(
            url: URL(string: "https://app.flipcash.com/g/\(byte)")!,
            chatID: ConversationID(data: Data(repeating: byte, count: 32)),
            range: NSRange(location: 0, length: 10)
        ))
    }

    private static func resolvedGroup(_ title: String) -> LinkCard.State {
        .group(.resolved(.init(
            title: title,
            memberCount: "12 members",
            avatarID: title,
            imageData: nil,
            blurHash: nil,
            requirement: "Hold $5 to join"
        )))
    }

    private func carded(_ id: String, _ text: String, card: LinkCard?, receipt: ChatReceipt? = nil) -> ChatItem {
        .message(ChatMessage(
            id: id,
            text: text,
            sender: .other,
            receipt: receipt,
            linkPreview: card.map { LinkPreview(links: [], card: $0) }
        ))
    }

    /// Lets the cards' subscription tasks run without letting the batch animations finish.
    private func spin() async {
        for _ in 0..<3 { await Task.yield() }
    }

    private func scrolledTranscript(seed: [ChatItem], source: Source, centeredOn row: Int) async -> WindowedTranscript {
        let controller = ChatViewController()
        controller.linkCardSource = source
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: seed)
        await settle(controller)
        controller.collectionView.scrollToItem(at: IndexPath(item: row, section: 0), at: .centeredVertically, animated: false)
        await settle(controller)
        return WindowedTranscript(window: window, controller: controller)
    }

    @Test("A neighbour's card grows while a scrolled-up row loses its card, then that row is edited")
    func neighbourCardGrows_whileRowFlips_scrolledUp() async {
        let source = Source()
        let g = Self.groupCard(1)
        let x = Self.groupCard(2)
        let above = history(30)
        let below = Array(history(60).suffix(30))
        let transcript = await scrolledTranscript(
            seed: above + [carded("g", "join", card: g), carded("x", "this one", card: x)] + below,
            source: source,
            centeredOn: 31
        )

        transcript.controller.update(items: above + [carded("g", "join", card: g), carded("x", "this one", card: nil)] + below)
        source.answer(g, Self.resolvedGroup("Grown"))
        source.answer(x, Self.resolvedGroup("Gone"))
        await spin()
        let final = above + [carded("g", "join", card: g), carded("x", "this one (edited)", card: nil)] + below
        transcript.controller.update(items: final)
        await settle(transcript.controller)

        expectLiveClassesMatch(transcript.controller, final)
        withExtendedLifetime(source) {}
    }

    @Test("A card grows between two pushes that flip its own row's class and back, scrolled up")
    func cardGrowsBetweenFlips_scrolledUp() async {
        let source = Source()
        let x = Self.groupCard(3)
        let above = history(30)
        let below = Array(history(60).suffix(30))
        let transcript = await scrolledTranscript(seed: above + [carded("x", "this one", card: x)] + below, source: source, centeredOn: 30)

        transcript.controller.update(items: above + [carded("x", "this one", card: nil)] + below)
        await spin()
        transcript.controller.update(items: above + [carded("x", "this one", card: x)] + below)
        source.answer(x, Self.resolvedGroup("Grown"))
        await spin()
        let final = above + [carded("x", "this one", card: x, receipt: .delivered)] + below
        transcript.controller.update(items: final)
        await settle(transcript.controller)

        expectLiveClassesMatch(transcript.controller, final)
        withExtendedLifetime(source) {}
    }

    /// Seeded so a failure replays: each round flips, edits, or appends rows and answers a few
    /// card lookups, with only a few task turns between pushes so batches overlap and cards
    /// resize while rows are mid-flight.
    @Test("Seeded churn of class flips, edits, arrivals and card growth on a scrolled transcript", arguments: [1, 7, 42, 1337, 2026])
    func seededChurn_scrolledUp(seed: UInt64) async {
        var rng = SplitMix(seed: seed)
        let source = Source()
        let cards = (10..<22).map { Self.groupCard(UInt8($0)) }
        var rows: [(id: String, text: String, card: LinkCard?)] = (0..<60).map { i in
            (id: "r\(i)", text: "row \(i)", card: i % 5 == 0 ? cards[(i / 5) % cards.count] : nil)
        }
        func items() -> [ChatItem] { rows.map { carded($0.id, $0.text, card: $0.card) } }

        let transcript = await scrolledTranscript(seed: items(), source: source, centeredOn: 30)
        var next = 60
        for round in 0..<40 {
            for _ in 0..<Int(rng.next() % 3 + 1) {
                let i = Int(rng.next() % UInt64(rows.count))
                switch rng.next() % 3 {
                case 0: rows[i].card = rows[i].card == nil ? cards[Int(rng.next() % UInt64(cards.count))] : nil
                case 1: rows[i].text += "."
                default:
                    rows.append((id: "r\(next)", text: "row \(next)", card: rng.next() % 2 == 0 ? cards[next % cards.count] : nil))
                    next += 1
                }
            }
            transcript.controller.update(items: items())
            for _ in 0..<Int(rng.next() % 3) {
                let card = cards[Int(rng.next() % UInt64(cards.count))]
                source.answer(card, Self.resolvedGroup("g\(round)-\(rng.next() % 100)"))
            }
            await spin()
        }
        await settle(transcript.controller)

        expectLiveClassesMatch(transcript.controller, items())
        withExtendedLifetime(source) {}
    }

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
