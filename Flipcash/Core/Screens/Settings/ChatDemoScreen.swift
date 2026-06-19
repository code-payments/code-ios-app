//
//  ChatDemoScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if DEBUG
import SwiftUI
import UIKit
import FlipcashUI

/// A throwaway harness to feel the new fully-UIKit chat on device. SwiftUI does only two
/// things here: host the UIKit `ChatScreenViewController` and feed it fake data. The transcript,
/// composer bar, and keyboard handling are all UIKit. Reachable from Settings ▸ Advanced in
/// DEBUG builds only.
struct ChatDemoScreen: View {

    @Environment(\.dismiss) private var dismiss
    @State private var harness = ChatDemoHarness()

    var body: some View {
        ZStack(alignment: .top) {
            ChatScreenHost(controller: harness.screen)
                .ignoresSafeArea()
            HStack {
                Button("Receive") { harness.receive() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .ignoresSafeArea(.keyboard) // the UIKit screen owns keyboard handling
    }
}

/// Owns the UIKit screen and the fake data, wiring paging + send/receive. The chat stays dumb:
/// this is the only thing that knows where messages come from.
@MainActor
@Observable
final class ChatDemoHarness {

    let screen: ChatScreenViewController

    private let composer = ChatComposerBar()
    private let pager: ChatHistoryPager
    private var appended: [ChatMessage] = []
    private var sentCount = 0
    private var receivedCount = 0

    init() {
        let full = ChatMessage.demoConversation(count: 200)
        let windowSize = 30
        pager = ChatHistoryPager(
            initial: Array(full.suffix(windowSize)),
            source: StaticOlderMessageSource(
                olderHistory: Array(full.prefix(full.count - windowSize)),
                pageSize: 25,
                latency: .milliseconds(250)
            )
        )
        screen = ChatScreenViewController(barView: composer)
        pager.onChange = { [weak self] _ in self?.push() }
        screen.onReachTop = { [weak self] in
            guard let self, !pager.isLoadingOlder, pager.hasMoreOlder else { return }
            Task { await pager.loadOlderPage() }
        }
        composer.onSend = { [weak self] text in self?.send(text) }
        push()
    }

    private func push() { screen.update(items: (pager.messages + appended).map { .message($0) }) }

    func send(_ text: String) {
        sentCount += 1
        appended.append(ChatMessage(id: "sent-\(sentCount)", text: text, sender: .me))
        push()
        screen.scrollToBottom(animated: true)
    }

    func receive() {
        receivedCount += 1
        appended.append(ChatMessage(id: "recv-\(receivedCount)", text: "Incoming message \(receivedCount) — should NOT auto-scroll.", sender: .other))
        push()
    }
}

private struct ChatScreenHost: UIViewControllerRepresentable {
    let controller: ChatScreenViewController
    func makeUIViewController(context: Context) -> ChatScreenViewController { controller }
    func updateUIViewController(_ controller: ChatScreenViewController, context: Context) {}
}

private extension ChatMessage {
    /// A varied sample conversation; the trailing `#<index>` lets you watch paging march
    /// toward `#0` (the first message) as you scroll up.
    static func demoConversation(count: Int) -> [ChatMessage] {
        let lines = [
            "Hey, you around?",
            "Yeah, what's up",
            "Just sent you a few bucks for lunch 🍔",
            "Oh nice — thank you!",
            "This is a longer message so we can watch the bubble wrap across several lines and confirm the cells self-size correctly while scrolling fast.",
            "np",
            "Want to split the ticket tonight?",
            "Sure — I'll cover drinks, you grab the food?",
            "Deal 🤝",
            "👍",
            "See you at 7",
            "Running 5 min late, sorry!",
            "all good",
        ]
        let senders: [Sender] = (0..<count).map { $0 % 4 == 0 || $0 % 7 == 0 ? .other : .me }
        return (0..<count).map { i in
            let continuesAbove = i > 0 && senders[i - 1] == senders[i]
            let continuesBelow = i < count - 1 && senders[i + 1] == senders[i]
            let content: ChatMessage.Content = i % 11 == 5
                ? .cash(ChatCashContent(amount: "$\(5 + i % 20).00", token: "Cash", flagImageName: "us"))
                : .text("\(lines[i % lines.count]) (#\(i))")
            return ChatMessage(
                id: "demo-\(i)",
                content: content,
                sender: senders[i],
                isContinuationFromPrevious: continuesAbove,
                isContinuedByNext: continuesBelow
            )
        }
    }
}
#endif
