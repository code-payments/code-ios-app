//
//  ChatHistoryPager.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Supplies older history on demand. Injected into `ChatHistoryPager` so the chat module
/// never reaches for the network itself — the app provides a concrete loader, while previews
/// and tests provide a fake one.
@MainActor
public protocol OlderMessageProviding: AnyObject {
    /// Whether any history exists before the currently loaded window.
    var hasMoreOlder: Bool { get }
    /// Fetch the next older page, oldest-first. An empty result means history is exhausted.
    func loadOlder() async -> [ChatMessage]
}

/// Owns the loaded transcript window and pages older history in from an injected source.
///
/// Idempotent by design: `loadOlderPage()` is a no-op while a load is in flight or history is
/// exhausted. That is what lets the controller ask on every scroll frame near the top without
/// stacking duplicate requests — and what makes it impossible to get stuck on a page.
@MainActor
public final class ChatHistoryPager {

    public private(set) var messages: [ChatMessage]
    /// Fired after an older page merges, carrying the full transcript to render.
    public var onChange: (([ChatMessage]) -> Void)?

    private let source: OlderMessageProviding
    private var isLoading = false

    public var hasMoreOlder: Bool { source.hasMoreOlder }
    public var isLoadingOlder: Bool { isLoading }

    public init(initial: [ChatMessage], source: OlderMessageProviding) {
        messages = initial
        self.source = source
    }

    /// Load the next older page and prepend it to the window. Returns whether a page merged.
    @discardableResult
    public func loadOlderPage() async -> Bool {
        guard !isLoading, source.hasMoreOlder else { return false }
        isLoading = true
        defer { isLoading = false }
        let older = await source.loadOlder()
        guard !older.isEmpty else { return false }
        messages = older + messages
        onChange?(messages)
        return true
    }
}

#if DEBUG
/// A fake history source for previews and tests: holds older messages and hands them back one
/// page at a time, newest-of-the-remaining first, until exhausted.
@MainActor
public final class StaticOlderMessageSource: OlderMessageProviding {

    private var remaining: [ChatMessage]
    private let pageSize: Int
    /// Artificial latency so previews show paging happen over time; `.zero` in tests.
    private let latency: Duration

    public var hasMoreOlder: Bool { !remaining.isEmpty }

    public init(olderHistory: [ChatMessage], pageSize: Int, latency: Duration = .zero) {
        remaining = olderHistory
        self.pageSize = pageSize
        self.latency = latency
    }

    public func loadOlder() async -> [ChatMessage] {
        if latency != .zero { try? await Task.sleep(for: latency) }
        let count = min(pageSize, remaining.count)
        guard count > 0 else { return [] }
        let page = Array(remaining.suffix(count))
        remaining.removeLast(count)
        return page
    }
}
#endif

#if DEBUG && canImport(UIKit)
import UIKit

/// Retains the controller, pager, and source and wires them together — paging older messages
/// in as you scroll toward the top.
private final class PaginatingChatPreviewController: UIViewController {

    private let chat = ChatViewController()
    private let pager: ChatHistoryPager

    init() {
        let full = ChatMessage.previewConversation(count: 120)
        let windowSize = 25
        let initial = Array(full.suffix(windowSize))
        let older = Array(full.prefix(full.count - windowSize))
        pager = ChatHistoryPager(
            initial: initial,
            source: StaticOlderMessageSource(olderHistory: older, pageSize: 20, latency: .milliseconds(300))
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(chat)
        chat.view.frame = view.bounds
        chat.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(chat.view)
        chat.didMove(toParent: self)

        chat.update(messages: pager.messages)
        pager.onChange = { [weak chat] messages in chat?.update(messages: messages) }
        chat.onReachTop = { [weak self] in
            guard let self, !pager.isLoadingOlder, pager.hasMoreOlder else { return }
            Task { await pager.loadOlderPage() }
        }
    }
}

#Preview("Paginating") {
    PaginatingChatPreviewController()
}
#endif
