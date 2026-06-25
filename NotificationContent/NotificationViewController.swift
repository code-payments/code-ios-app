//
//  NotificationViewController.swift
//  NotificationContent
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import SwiftUI
import UserNotifications
import UserNotificationsUI
import FlipcashCore
import FlipcashUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    // MARK: - Properties -

    /// The app's real chat transcript, embedded so the preview renders, sizes, scrolls,
    /// and opens at the newest message exactly like the in-app chat.
    private let chat = ChatViewController()
    private var statusLabel: UILabel?

    /// The dark "background" color (display-P3 25,25,26), hardcoded because the matching asset
    /// lives in the app bundle and can't resolve from this extension.
    private static let chatBackground = UIColor(
        displayP3Red: 25 / 255, green: 25 / 255, blue: 26 / 255, alpha: 1
    )

    /// Recent messages to show, and how often to re-check the server while expanded.
    private static let previewLimit = 3
    private static let pollInterval: TimeInterval = 2.5
    /// The panel sizes to its content up to this; taller transcripts scroll (newest pinned
    /// at the bottom) instead of clipping, like the chat screen.
    private static let maxContentHeight: CGFloat = 440

    private lazy var client = ChatNotificationClient()
    private var conversationID: ConversationID?
    private var ownerKeyPair: KeyPair?
    private var selfUserID: UserID?
    private var pollTask: Task<Void, Never>?
    /// True once messages have been rendered, so polling/reply failures don't clobber them
    /// and the panel sizing kicks in.
    private var hasContent = false
    /// Resolved token branding (name + coin icon) keyed by mint, so cash bubbles read "Jeffy"
    /// with its icon. Cached across polls so each mint is fetched at most once.
    private var mintBranding: [PublicKey: (name: String, iconURL: URL?)] = [:]
    /// Serializes `loadMessages`: the initial load and the 2.5s poll otherwise interleave their
    /// `chat.update` calls when a fetch is slow, and overlapping transcript reloads corrupt the
    /// diff and blank the panel.
    private var isLoading = false

    // MARK: - Lifecycle -

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Self.chatBackground
        FontBook.registerApplicationFonts()

        addChild(chat)
        chat.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chat.view)
        NSLayoutConstraint.activate([
            chat.view.topAnchor.constraint(equalTo: view.topAnchor),
            chat.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chat.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chat.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        chat.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard hasContent else { return }
        updatePanelSize()
    }

    /// Sizes the panel to the transcript's content height (capped) — short conversations
    /// fit exactly, taller ones cap and scroll. Reads ChatLayout's `contentSize`, which is
    /// the true content height (bottom-anchoring only offsets cells, it doesn't pad it).
    private func updatePanelSize() {
        let target = max(min(chat.collectionView.contentSize.height, Self.maxContentHeight), 44)
        if abs(preferredContentSize.height - target) > 0.5 {
            preferredContentSize = CGSize(width: view.bounds.width, height: target)
        }
    }

    // MARK: - UNNotificationContentExtension -

    func didReceive(_ notification: UNNotification) {
        guard let conversationID = NotificationPayload.chatID(
            notification.request.content.userInfo
        ) else {
            // Not a chat push — leave the default banner.
            return
        }
        guard let account = OwnerKeyStore.loadOwnerAccount() else {
            // Owner key unavailable (e.g. before first unlock) — hint rather than blank.
            showStatusLabel("Open Flipcash to view this message")
            return
        }
        self.conversationID = conversationID
        self.ownerKeyPair = account.keyAccount.owner
        self.selfUserID = account.userID

        Task { @MainActor in await loadMessages() }
        startPolling()
    }

    func didReceive(
        _ response: UNNotificationResponse,
        completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void
    ) {
        switch response.actionIdentifier {

        case ChatNotificationCategory.replyActionID:
            guard
                let textResponse = response as? UNTextInputNotificationResponse,
                let conversationID,
                let ownerKeyPair
            else {
                completion(.dismiss)
                return
            }

            let text = textResponse.userText
            Task { @MainActor in
                do {
                    _ = try await client.sendMessage(
                        owner: ownerKeyPair,
                        conversationID: conversationID,
                        text: text
                    )
                    // Re-fetch so the sent message appears in the transcript.
                    await loadMessages()
                } catch {
                    // Leave the transcript as-is; the message simply wasn't sent.
                }
                completion(.doNotDismiss)
            }

        case ChatNotificationCategory.sendCashActionID:
            completion(.dismissAndForwardAction)

        default:
            completion(.dismiss)
        }
    }

    // MARK: - Loading -

    /// Fetches recent messages and feeds them to the transcript. Safe to call repeatedly
    /// (the poll does); a transient failure keeps whatever is already shown.
    @MainActor
    private func loadMessages() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let conversationID, let ownerKeyPair, let selfUserID else { return }
        do {
            let messages = try await client.getMessages(
                owner: ownerKeyPair,
                conversationID: conversationID,
                limit: Self.previewLimit
            )
            if messages.isEmpty {
                if !hasContent { showStatusLabel("No messages") }
            } else {
                clearStatusLabel()
                hasContent = true
                // Render immediately with whatever names are cached (currency-code fallback for
                // any new mint), then resolve missing token names over the network and re-render
                // so they swap in — the bubble is never gated on that round-trip.
                render(messages, selfUserID: selfUserID)
                if await resolveMintBranding(in: messages) {
                    render(messages, selfUserID: selfUserID)
                }
            }
        } catch {
            if !hasContent { showStatusLabel("Couldn't load messages") }
        }
    }

    private func render(_ messages: [ConversationMessage], selfUserID: UserID) {
        chat.update(items: ChatItem.preview(
            from: messages,
            selfUserID: selfUserID,
            limit: Self.previewLimit,
            mintBranding: mintBranding
        ), animated: false)
        // The transcript lays out asynchronously and the parent won't re-lay out on its
        // own, so force the layout now and size the panel to the real content.
        chat.collectionView.layoutIfNeeded()
        updatePanelSize()
    }

    /// Resolves token branding (name + icon) for cash mints not already cached, over the network —
    /// the extension has no SQLite mint cache, so it asks the server directly. Returns true if the
    /// cache changed (caller re-renders). Best-effort: a failed lookup leaves the row unbranded.
    @MainActor
    private func resolveMintBranding(in messages: [ConversationMessage]) async -> Bool {
        let unresolved = Set(messages.compactMap { message -> PublicKey? in
            guard case .cash(let fiat) = message.content, mintBranding[fiat.mint] == nil else { return nil }
            return fiat.mint
        })
        guard !unresolved.isEmpty else { return false }
        guard let resolved = try? await client.fetchMintMetadata(for: Array(unresolved)), !resolved.isEmpty else {
            return false
        }
        for (mint, metadata) in resolved {
            mintBranding[mint] = (name: metadata.name, iconURL: metadata.imageURL)
        }
        return true
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollInterval))
                if Task.isCancelled { break }
                await self?.loadMessages()
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Status UI -

    private func showStatusLabel(_ text: String) {
        clearStatusLabel()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.numberOfLines = 0
        label.textColor = UIColor(Color.textMain)
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        statusLabel = label
        preferredContentSize = CGSize(width: view.bounds.width, height: 120)
    }

    private func clearStatusLabel() {
        statusLabel?.removeFromSuperview()
        statusLabel = nil
    }
}
