//
//  NotificationViewController.swift
//  NotificationContent
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import SwiftUI
import os
import UserNotifications
import UserNotificationsUI
import FlipcashCore
import FlipcashUI

/// Thrown when the first preview read comes back empty, so `Task.retry` re-fetches — a message that
/// just triggered this push may lose the read-after-write race against the first request.
private struct EmptyPreview: Error {}

final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    // MARK: - Properties -

    /// A lightweight SwiftUI transcript hosting the recent messages as a bottom-anchored bubble
    /// list. Deliberately NOT the in-app `ChatViewController` (UICollectionView + custom
    /// `ChatLayout`), whose footprint exceeds a content extension's memory budget and gets it
    /// jetsam-killed. The panel keeps one fixed height; the transcript scrolls within it.
    private let transcript = UIHostingController(rootView: NotificationTranscriptView(items: []))
    private var statusLabel: UILabel?

    /// The dark "background" color (display-P3 25,25,26), hardcoded because the matching asset
    /// lives in the app bundle and can't resolve from this extension.
    private static let chatBackground = UIColor(
        displayP3Red: 25 / 255, green: 25 / 255, blue: 26 / 255, alpha: 1
    )

    /// Recent messages to show, and how often to re-check the server while expanded.
    private static let previewLimit = 5
    private static let pollInterval: TimeInterval = 2.5
    /// The panel's fixed height. It never resizes to fit the transcript (which scrolls within
    /// it), so the height stays put instead of jumping as messages load.
    private static let fixedPanelHeight: CGFloat = 300
    /// Breathing room below the newest bubble so it isn't flush against the panel's bottom edge.
    private static let bottomInset: CGFloat = 16

    private static let logger = Logger(label: "flipcash.notification-content")
    /// Created in `viewDidLoad`; nil only when the gRPC clients can't be built (logged).
    private var client: ChatNotificationClient?
    private var conversationID: ConversationID?
    private var ownerKeyPair: KeyPair?
    private var selfUserID: UserID?
    private var pollTask: Task<Void, Never>?
    /// The in-flight reply send, tracked so a rapid re-open cancels the previous one instead of
    /// stacking tasks that retain the client + completion closure.
    private var replyTask: Task<Void, Never>?
    /// True once messages have been rendered, so polling/reply failures don't clobber them.
    private var hasContent = false
    /// Resolved token branding (name + coin icon) keyed by mint, so cash bubbles read "Jeffy"
    /// with its icon. Cached across polls so each mint is fetched at most once.
    private var mintBranding: [PublicKey: MintBrandingInfo] = [:]
    /// Serializes `loadMessages`: the initial load and the 2.5s poll otherwise interleave their
    /// `chat.update` calls when a fetch is slow, and overlapping transcript reloads corrupt the
    /// diff and blank the panel.
    private var isLoading = false

    // MARK: - Lifecycle -

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Self.chatBackground
        // Fix the panel height up front. A content extension with the default content hidden
        // takes its height from preferredContentSize — leave it unset and the panel collapses
        // and dismisses, so pin it here and never resize it to the transcript.
        preferredContentSize = CGSize(width: view.bounds.width, height: Self.fixedPanelHeight)
        FontBook.registerNotificationFonts()
        do {
            client = try ChatNotificationClient()
        } catch {
            Self.logger.error("Failed to create the notification gRPC client", metadata: ["error": "\(error)"])
        }

        addChild(transcript)
        // The panel sits above the reply keyboard, so don't let the keyboard's safe area inset the
        // transcript (which pushes the messages up and leaves a gap). Dropping the keyboard region
        // from the hosting controller is a UIKit-level toggle that leaves the SwiftUI layout untouched.
        transcript.safeAreaRegions = .container
        transcript.view.translatesAutoresizingMaskIntoConstraints = false
        transcript.view.backgroundColor = .clear
        view.addSubview(transcript.view)
        NSLayoutConstraint.activate([
            transcript.view.topAnchor.constraint(equalTo: view.topAnchor),
            transcript.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transcript.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transcript.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.bottomInset),
        ])
        transcript.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A status hint (e.g. "Open Flipcash…") sizes itself compactly; don't fight it.
        guard statusLabel == nil else { return }
        // Re-assert the fixed height in case the system reset it (which would collapse the
        // panel); the guard keeps this a no-op once it's set, so the panel never resizes.
        let target = Self.fixedPanelHeight
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
                let ownerKeyPair,
                let client
            else {
                completion(.dismiss)
                return
            }

            let text = textResponse.userText
            replyTask?.cancel()
            replyTask = Task { @MainActor in
                do {
                    _ = try await Task.retry(maxAttempts: 3, delay: .milliseconds(400)) {
                        try await client.sendMessage(owner: ownerKeyPair, conversationID: conversationID, text: text)
                    }
                    // Re-fetch so the sent message appears in the transcript.
                    await loadMessages()
                } catch {
                    Self.logger.error("Failed to send the notification reply", metadata: ["error": "\(error)"])
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
        guard let conversationID, let ownerKeyPair, let selfUserID, let client else { return }
        do {
            // On the first load, retry an empty/failed read to dodge the read-after-write race;
            // later polls take a single shot (an empty poll just means no new messages).
            let messages = try await fetchPreview(
                client: client,
                owner: ownerKeyPair,
                conversationID: conversationID,
                retryOnEmpty: !hasContent
            )
            if messages.isEmpty {
                if !hasContent { showStatusLabel("No messages") }
            } else {
                clearStatusLabel()
                let isFirstRender = !hasContent
                hasContent = true
                // Render immediately with whatever names are cached (currency-code fallback for
                // any new mint), then resolve missing token names over the network and re-render
                // so they swap in — the bubble is never gated on that round-trip.
                render(messages, selfUserID: selfUserID)
                if isFirstRender {
                    Self.logger.info("Notification transcript rendered", metadata: [
                        "availableMemoryMB": "\(os_proc_available_memory() / (1024 * 1024))",
                    ])
                }
                if await resolveMintBranding(in: messages) {
                    render(messages, selfUserID: selfUserID)
                }
            }
        } catch {
            if !hasContent { showStatusLabel("Couldn't load messages") }
        }
    }

    /// Fetches the recent messages, retrying an empty or failed read a few times when `retryOnEmpty`
    /// (the first load) so a just-arrived message isn't missed to the read-after-write race. An empty
    /// result after the retries is returned as `[]` (genuinely no messages), not an error.
    private func fetchPreview(
        client: ChatNotificationClient,
        owner: KeyPair,
        conversationID: ConversationID,
        retryOnEmpty: Bool
    ) async throws -> [ConversationMessage] {
        guard retryOnEmpty else {
            return try await client.getMessages(owner: owner, conversationID: conversationID, limit: Self.previewLimit)
        }
        do {
            return try await Task.retry(maxAttempts: 4, delay: .milliseconds(250)) {
                let messages = try await client.getMessages(owner: owner, conversationID: conversationID, limit: Self.previewLimit)
                if messages.isEmpty { throw EmptyPreview() }
                return messages
            }
        } catch is EmptyPreview {
            return []
        }
    }

    private func render(_ messages: [ConversationMessage], selfUserID: UserID) {
        transcript.rootView = NotificationTranscriptView(items: ChatItem.preview(
            from: messages,
            selfUserID: selfUserID,
            limit: Self.previewLimit,
            mintBranding: mintBranding
        ))
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
        guard !unresolved.isEmpty, let client else { return false }
        let resolved: [PublicKey: MintMetadata]
        do {
            resolved = try await client.fetchMintMetadata(for: Array(unresolved))
        } catch {
            Self.logger.error("Failed to resolve mint metadata", metadata: ["error": "\(error)"])
            return false
        }
        guard !resolved.isEmpty else { return false }
        for (mint, metadata) in resolved {
            mintBranding[mint] = MintBrandingInfo(name: metadata.name, iconURL: metadata.imageURL)
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
        replyTask?.cancel()
        replyTask = nil
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
        // Restore the fixed transcript height — a status hint had shrunk the panel to 120.
        preferredContentSize = CGSize(width: view.bounds.width, height: Self.fixedPanelHeight)
    }
}
