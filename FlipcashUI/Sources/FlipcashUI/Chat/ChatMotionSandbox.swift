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

/// A real transcript driven by a scripted send, so the send moment can be watched and recorded
/// without a server, an account, or a counterpart.
///
/// The whole point is that it is the *shipping* controller: `ChatViewController` and its cells,
/// updated the way `ConversationScreen` updates them. Anything seen here is what the app does. The
/// script is deterministic and single-shot, which is what makes a before/after pair of recordings
/// comparable — the same beats, at the same offsets, on both sides of a change.
public final class ChatMotionSandboxViewController: UIViewController {

    /// The scripted send, beat by beat. Each beat's delay is the wait *before* it runs.
    private enum Beat {
        /// The row lands in the transcript with no receipt: insertion spring, scroll-to-bottom.
        case send
        /// The settle floor expires and the receipt reveals.
        case delivered
        /// Delivered gives way to Read: the in-place swap.
        case read
        /// Back to the resting transcript, un-animated, ready to run again.
        case reset

        var delay: Duration {
            switch self {
            case .send:      .seconds(1)
            // Mirrors `ReceiptSettleGate.defaultDelay`, which lives in the app target and isn't
            // reachable from here. If that floor moves, move this with it.
            case .delivered: .milliseconds(700)
            case .read:      .seconds(1.4)
            case .reset:     .seconds(2)
            }
        }

        var receipt: ChatReceipt? {
            switch self {
            case .send:      nil
            case .delivered: .delivered
            case .read:      .read(time: "3:42 PM")
            case .reset:     nil
            }
        }
    }

    private static let script: [Beat] = [.send, .delivered, .read, .reset]

    /// The resting transcript the script runs on top of. Ends on a `.me` run, so the scripted send
    /// is a continuation and its top corner flattens — which is what makes the corner morph visible.
    private let base: [ChatItem] = ChatMessage.previewConversation(count: 8).map { .message($0) }

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

        runButton.setTitle("Run send", for: .normal)
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

        transcript.update(items: base, animated: false)
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
        // the first — two overlapping sends would make the recording unreadable.
        guard run == nil else {
            run?.cancel()
            run = nil
            transcript.update(items: base, animated: false)
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

    /// Plays the script once. Every beat replaces the same row id, so the transcript sees an in-place
    /// update — which is the condition the receipt animates on.
    private func play() async {
        for beat in Self.script {
            try? await Task.sleep(for: beat.delay)
            guard !Task.isCancelled else { return }
            switch beat {
            case .reset:
                transcript.update(items: base, animated: false)
            case .send, .delivered, .read:
                let sent = ChatMessage(
                    id: "motion-send",
                    text: "Sent just now",
                    sender: .me,
                    isContinuationFromPrevious: true,
                    receipt: beat.receipt
                )
                transcript.update(items: base + [.message(sent)])
            }
        }
    }
}

#Preview("Motion sandbox") {
    ChatMotionSandboxViewController()
}
#endif
