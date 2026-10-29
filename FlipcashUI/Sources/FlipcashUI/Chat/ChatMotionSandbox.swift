//
//  ChatMotionSandbox.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// A real transcript driven by a scripted exchange, so the send moment, the receipt, the typing
/// dots and the reply can be watched and recorded without a server, an account, or a counterpart.
///
/// The whole point is that it is the *shipping* controller: `ChatViewController` and its cells,
/// updated the way `ConversationScreen` updates them. Anything seen here is what the app does. The
/// script is deterministic and single-shot, which is what makes a before/after pair of recordings
/// comparable — the same beats, at the same offsets, on both sides of a change.
public final class ChatMotionSandboxViewController: UIViewController {

    /// The scripted exchange, beat by beat. Each beat's delay is the wait *before* it runs.
    private enum Beat {
        /// The row lands in the transcript with no receipt while the row above keeps its
        /// "Delivered": insertion spring, scroll-to-bottom.
        case sending
        /// The settle floor expires and the line moves, in one update: the row above gives it up as
        /// the new row reveals it.
        case delivered
        /// Delivered gives way to Read: the in-place swap.
        case read
        /// The counterpart starts typing: the dots bubble arrives off the leading edge.
        case typing
        /// The dots turn into the reply — one update, so the reply's bubble grows out of the dots'
        /// where they stood (`ChatViewController.typingHandoffRow`).
        case reply
        /// Back to the resting transcript, un-animated, ready to run again.
        case reset

        var delay: Duration {
            switch self {
            case .sending:   .seconds(1)
            // The floor a real send's receipt is held for. `ReceiptSettleGate.defaultDelay` lives in the
            // app target and isn't reachable from here, so the two move together by hand.
            case .delivered: .seconds(ChatMotion.deliveredDelay)
            case .read:      .seconds(1.4)
            case .typing:    .seconds(0.9)
            // Two full turns of the dot wave (`ChatTypingIndicatorCell.wavePeriod`) before the
            // reply cuts it off, so the wave is legible rather than a flicker.
            case .reply:     .seconds(2.6)
            case .reset:     .seconds(2)
            }
        }
    }

    private static let script: [Beat] = [.sending, .delivered, .read, .typing, .reply, .reset]

    /// The resting transcript the script runs on top of. Ends on a `.me` run, so the scripted send
    /// is a continuation and its top corner flattens — which is what makes the corner morph visible.
    private let base: [ChatMessage] = ChatMessage.previewConversation(count: 8)

    /// The line `base`'s trailing own row carries until the scripted send takes it over.
    private static let baseReceipt = ChatReceipt.delivered

    private static let readTime = "3:42 PM"

    private static func sent(receipt: ChatReceipt?) -> ChatMessage {
        ChatMessage(id: "motion-send", text: "Sent just now", sender: .me, receipt: receipt)
    }

    private static let reply = ChatMessage(id: "motion-reply", text: "Got it — see you at noon.", sender: .other)

    private let transcript = ChatViewController()
    private let runButton = UIButton(type: .system)
    private let loopSwitch = UISwitch()
    private let caption = UILabel()
    private var run: Task<Void, Never>?

    /// Plays the group script instead of the DM one.
    private let isGroup: Bool

    /// `autoplay` starts the script looping as soon as the screen appears. The recording path uses
    /// it — a recording that depends on a tap lands the beat at a different offset every take, and
    /// two takes that don't line up can't be compared frame for frame.
    private let autoplay: Bool

    /// `group` plays ``GroupScript`` — the group rows of the shared typing-dots handoff table, one
    /// scene each — instead of the DM exchange.
    public init(autoplay: Bool = false, group: Bool = false) {
        self.autoplay = autoplay
        self.isGroup = group
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(transcript)
        transcript.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transcript.view)
        transcript.didMove(toParent: self)

        runButton.setTitle("Run exchange", for: .normal)
        runButton.titleLabel?.font = .default(size: 15, weight: .bold)
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)

        let loopLabel = UILabel()
        loopLabel.text = "Loop"
        loopLabel.font = .default(size: 13, weight: .medium)
        loopLabel.textColor = .white.withAlphaComponent(0.5)

        caption.font = .default(size: 13, weight: .medium)
        caption.textColor = .white.withAlphaComponent(0.7)
        caption.numberOfLines = 2
        caption.isHidden = !isGroup

        let buttons = UIStackView(arrangedSubviews: [runButton, UIView(), loopLabel, loopSwitch])
        buttons.axis = .horizontal
        buttons.alignment = .center
        buttons.spacing = 8

        let controls = UIStackView(arrangedSubviews: [caption, buttons])
        controls.axis = .vertical
        controls.spacing = 4
        controls.isLayoutMarginsRelativeArrangement = true
        controls.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        NSLayoutConstraint.activate([
            transcript.view.topAnchor.constraint(equalTo: view.topAnchor),
            transcript.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transcript.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transcript.view.bottomAnchor.constraint(equalTo: controls.topAnchor),

            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        resetTranscript()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard autoplay, run == nil else { return }
        loopSwitch.isOn = true
        start()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        run?.cancel()
        run = nil
    }

    @objc private func runTapped() {
        // A second tap while a run is in flight stops it rather than racing a second script against
        // the first — two overlapping exchanges would make the recording unreadable.
        guard run == nil else {
            run?.cancel()
            run = nil
            resetTranscript()
            return
        }
        start()
    }

    private func start() {
        run = Task { @MainActor [weak self] in
            repeat {
                guard let self, !Task.isCancelled else { return }
                await play()
            } while self?.loopSwitch.isOn == true
            self?.run = nil
        }
    }

    /// Plays the script once. Every beat hands over the whole transcript, so the controller sees a
    /// plain diff against the last one — which is the condition the receipt and the corners
    /// animate on.
    private func play() async {
        guard !isGroup else { return await playGroup() }
        for beat in Self.script {
            try? await Task.sleep(for: beat.delay)
            guard !Task.isCancelled else { return }
            switch beat {
            case .reset:
                transcript.update(items: items(at: beat), animated: false)
            case .sending, .delivered, .read, .typing, .reply:
                transcript.update(items: items(at: beat))
            }
        }
    }

    private func resetTranscript() {
        if isGroup {
            caption.text = nil
            transcript.update(items: GroupScript.items(GroupScript.base, typing: []), animated: false)
        } else {
            transcript.update(items: items(at: .reset), animated: false)
        }
    }

    /// Plays the group script once, captioning each scene with the table row it shows.
    private func playGroup() async {
        var messages = GroupScript.base
        for scene in GroupScript.scenes {
            try? await Task.sleep(for: scene.delay)
            guard !Task.isCancelled else { return }
            messages += scene.arrivals
            caption.text = scene.caption
            transcript.update(items: GroupScript.items(messages, typing: scene.typing))
        }
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        resetTranscript()
    }

    /// The whole transcript as of `beat`.
    private func items(at beat: Beat) -> [ChatItem] {
        switch beat {
        case .reset:     items(appending: [], baseReceipt: Self.baseReceipt)
        case .sending:   items(appending: [Self.sent(receipt: nil)], baseReceipt: Self.baseReceipt)
        case .delivered: items(appending: [Self.sent(receipt: .delivered)])
        case .read:      items(appending: [Self.sent(receipt: .read(time: Self.readTime))])
        case .typing:    items(appending: [Self.sent(receipt: .read(time: Self.readTime))], typing: true)
        case .reply:     items(appending: [Self.sent(receipt: .read(time: Self.readTime)), Self.reply])
        }
    }

    /// `base` plus `tail`, regrouped, with the dots bubble on the end when the counterpart is
    /// typing. The dots are appended after the grouping pass and never join a run, matching
    /// `ConversationLoadCoordinator.map`.
    ///
    /// `baseReceipt` is the line `base`'s last row still carries: its own until the scripted send
    /// takes it, as the transcript mapping keeps it there while a send settles.
    private func items(appending tail: [ChatMessage], baseReceipt: ChatReceipt? = nil, typing: Bool = false) -> [ChatItem] {
        let held = base.last.map { (id: $0.id, receipt: baseReceipt) }
        var items = Self.grouped(base + tail, held: held).map { ChatItem.message($0) }
        if typing {
            items.append(.typingIndicator(typists: []))
        }
        return items
    }

    /// Recomputes the same-sender grouping flags across the whole list from sender adjacency alone.
    /// No sandbox row renders bare, so unlike `ChatItem.from` this never breaks the bubble run around
    /// one; only a receipt does. Without recomputing at all, the row above an
    /// arrival keeps the flags it was built with, so its inner corner never flattens and the morph
    /// has nothing to animate.
    ///
    /// `held` overrides one row's receipt.
    private static func grouped(_ messages: [ChatMessage], held: (id: String, receipt: ChatReceipt?)?) -> [ChatMessage] {
        let receipts = messages.map { $0.id == held?.id ? held?.receipt : $0.receipt }
        return messages.enumerated().map { index, message in
            let above = index > 0 && sameRun(messages[index - 1], message)
            let below = index < messages.count - 1 && sameRun(messages[index + 1], message)
            return ChatMessage(
                id: message.id,
                content: message.content,
                sender: message.sender,
                isContinuationFromPrevious: above,
                isContinuedByNext: below,
                // A receipt sits between the two bubbles, so it ends the run as the transcript's does.
                joinsBubbleAbove: above && receipts[index - 1] == nil,
                joinsBubbleBelow: below && receipts[index] == nil,
                receipt: receipts[index],
                linkPreview: message.linkPreview,
                author: message.author,
                isAttributedTranscript: message.isAttributedTranscript
            )
        }
    }

    /// Adjacent rows share a run when the same person wrote both. A DM's rows carry no author, so
    /// there the side alone decides.
    private static func sameRun(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        a.sender == b.sender && a.author?.id == b.author?.id
    }

    /// The group rows of the shared typing-dots handoff table (`docs/cross-platform-parity.md` in
    /// flipcash-client-orchestrator), played one scene at a time on a named-author transcript.
    private enum GroupScript {

        struct Scene {
            let delay: Duration
            let caption: String
            /// Appended in the same update the typist set changes in.
            let arrivals: [ChatMessage]
            /// Who is typing after the update, oldest first.
            let typing: [ChatAuthor]
        }

        static let ada = author(0, "Ada Lovelace")
        static let grace = author(1, "Grace Hopper")
        static let alan = author(2, "Alan Turing")

        private static func author(_ index: Int, _ name: String) -> ChatAuthor {
            ChatAuthor(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID(), name: name)
        }

        /// Every scripted text is distinct, so it doubles as the row id.
        private static func from(_ author: ChatAuthor?, _ text: String) -> ChatMessage {
            ChatMessage(
                id: "group-\(text)",
                text: text,
                sender: author == nil ? .me : .other,
                author: author,
                isAttributedTranscript: true
            )
        }

        static let base: [ChatMessage] = [
            from(ada, "Lunch at noon?"),
            from(grace, "I'm in"),
            from(nil, "Same, where?"),
        ]

        static let scenes: [Scene] = [
            Scene(delay: .seconds(1.2), caption: "Ada and Grace start typing", arrivals: [], typing: [ada, grace]),
            Scene(delay: .seconds(2.6), caption: "One of two sends: inserts above, dots stay for Grace",
                  arrivals: [from(ada, "The taco place?")], typing: [grace]),
            Scene(delay: .seconds(2.6), caption: "Non-typist sends: inserts above, dots stay",
                  arrivals: [from(alan, "Count me in")], typing: [grace]),
            Scene(delay: .seconds(2.6), caption: "Viewer sends: inserts above, dots stay",
                  arrivals: [from(nil, "Tacos it is")], typing: [grace]),
            Scene(delay: .seconds(2.2), caption: "Ada types again", arrivals: [], typing: [grace, ada]),
            Scene(delay: .seconds(2.6), caption: "Both send together: Ada (newest) takes the dots",
                  arrivals: [from(grace, "Booking a table"), from(ada, "Perfect")], typing: []),
            Scene(delay: .seconds(2.2), caption: "Ada types", arrivals: [], typing: [ada]),
            Scene(delay: .seconds(2.6), caption: "Newest arrival wasn't typing: both insert, dots exit",
                  arrivals: [from(ada, "12:15 works too"), from(alan, "See you there")], typing: []),
            Scene(delay: .seconds(2.2), caption: "Grace types", arrivals: [], typing: [grace]),
            Scene(delay: .seconds(2.6), caption: "The only typist sends: Grace takes the dots",
                  arrivals: [from(grace, "Table for four at noon")], typing: []),
        ]

        /// `messages` regrouped, with the dots row trailing them while anyone types.
        static func items(_ messages: [ChatMessage], typing: [ChatAuthor]) -> [ChatItem] {
            var items = ChatMotionSandboxViewController.grouped(messages, held: nil).map { ChatItem.message($0) }
            if !typing.isEmpty {
                items.append(.typingIndicator(typists: typing))
            }
            return items
        }
    }
}

#Preview("Motion sandbox") {
    ChatMotionSandboxViewController()
}
#endif
