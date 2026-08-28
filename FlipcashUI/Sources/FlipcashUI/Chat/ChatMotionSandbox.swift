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
        /// The row lands in the transcript with no receipt: insertion spring, scroll-to-bottom.
        case send
        /// The settle floor expires and the receipt reveals.
        case delivered
        /// Delivered gives way to Read: the in-place swap.
        case read
        /// The counterpart starts typing: the dots bubble arrives off the leading edge.
        case typing
        /// The dots give way to the reply — one update, so the incoming bubble takes the tail the
        /// dots were holding.
        case reply
        /// Back to the resting transcript, un-animated, ready to run again.
        case reset

        var delay: Duration {
            switch self {
            case .send:      .seconds(1)
            // Mirrors `ReceiptSettleGate.defaultDelay`, which lives in the app target and isn't
            // reachable from here. If that floor moves, move this with it.
            case .delivered: .milliseconds(700)
            case .read:      .seconds(1.4)
            case .typing:    .seconds(0.9)
            // Two full turns of the dot wave (`ChatTypingIndicatorCell.wavePeriod`) before the
            // reply cuts it off, so the wave is legible rather than a flicker.
            case .reply:     .seconds(2.6)
            case .reset:     .seconds(2)
            }
        }
    }

    private static let script: [Beat] = [.send, .delivered, .read, .typing, .reply, .reset]

    /// The resting transcript the script runs on top of. Ends on a `.me` run, so the scripted send
    /// is a continuation and its top corner flattens — which is what makes the corner morph visible.
    private let base: [ChatMessage] = ChatMessage.previewConversation(count: 8)

    private static let readTime = "3:42 PM"

    private static func sent(receipt: ChatReceipt?) -> ChatMessage {
        ChatMessage(id: "motion-send", text: "Sent just now", sender: .me, receipt: receipt)
    }

    private static let reply = ChatMessage(id: "motion-reply", text: "Got it — see you at noon.", sender: .other)

    private let transcript = ChatViewController()
    private let runButton = UIButton(type: .system)
    private let loopSwitch = UISwitch()
    private var run: Task<Void, Never>?

    /// `autoplay` starts the script looping as soon as the screen appears. The recording path uses
    /// it — a recording that depends on a tap lands the beat at a different offset every take, and
    /// two takes that don't line up can't be compared frame for frame.
    private let autoplay: Bool

    public init(autoplay: Bool = false) {
        self.autoplay = autoplay
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

        let controls = UIStackView(arrangedSubviews: [runButton, UIView(), loopLabel, loopSwitch])
        controls.axis = .horizontal
        controls.alignment = .center
        controls.spacing = 8
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

        transcript.update(items: items(at: .reset), animated: false)
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
            transcript.update(items: items(at: .reset), animated: false)
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
        for beat in Self.script {
            try? await Task.sleep(for: beat.delay)
            guard !Task.isCancelled else { return }
            switch beat {
            case .reset:
                transcript.update(items: items(at: beat), animated: false)
            case .send, .delivered, .read, .typing, .reply:
                transcript.update(items: items(at: beat))
            }
        }
    }

    /// The whole transcript as of `beat`.
    private func items(at beat: Beat) -> [ChatItem] {
        switch beat {
        case .reset:     items(appending: [])
        case .send:      items(appending: [Self.sent(receipt: nil)])
        case .delivered: items(appending: [Self.sent(receipt: .delivered)])
        case .read:      items(appending: [Self.sent(receipt: .read(time: Self.readTime))])
        case .typing:    items(appending: [Self.sent(receipt: .read(time: Self.readTime))], typing: true)
        case .reply:     items(appending: [Self.sent(receipt: .read(time: Self.readTime)), Self.reply])
        }
    }

    /// `base` plus `tail`, regrouped, with the dots bubble on the end when the counterpart is
    /// typing. The dots are appended after the grouping pass and never join a run, matching
    /// `ConversationLoadCoordinator.map`.
    private func items(appending tail: [ChatMessage], typing: Bool = false) -> [ChatItem] {
        var items = Self.grouped(base + tail).map { ChatItem.message($0) }
        if typing {
            items.append(.typingIndicator)
        }
        return items
    }

    /// Recomputes the same-sender grouping flags across the whole list, the way `ChatItem.from`
    /// does for the real transcript. Without it the row above an arrival keeps the flags it was
    /// built with, so its inner corner never flattens and the morph has nothing to animate.
    private static func grouped(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.enumerated().map { index, message in
            ChatMessage(
                id: message.id,
                content: message.content,
                sender: message.sender,
                isContinuationFromPrevious: index > 0 && messages[index - 1].sender == message.sender,
                isContinuedByNext: index < messages.count - 1 && messages[index + 1].sender == message.sender,
                receipt: message.receipt,
                linkPreview: message.linkPreview
            )
        }
    }
}

#Preview("Motion sandbox") {
    ChatMotionSandboxViewController()
}
#endif
