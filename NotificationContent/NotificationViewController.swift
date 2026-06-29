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

    /// The panel's fixed height. It never resizes to fit the transcript (which scrolls within
    /// it), so the height stays put instead of jumping as messages load.
    private static let fixedPanelHeight: CGFloat = 300
    /// Breathing room below the newest bubble so it isn't flush against the panel's bottom edge.
    private static let bottomInset: CGFloat = 16

    private static let logger = Logger(label: "flipcash.notification-content")
    private var conversationID: ConversationID?
    private var ownerKeyPair: KeyPair?
    private var selfUserID: UserID?
    /// The in-flight reply send, tracked so a rapid re-open cancels the previous one instead of
    /// stacking tasks that retain a client + completion closure.
    private var replyTask: Task<Void, Never>?
    /// The in-flight cache-miss live fetch, tracked so dismissing the panel tears down its transient
    /// connection instead of leaving it to run (and re-render) after the panel is gone.
    private var loadTask: Task<Void, Never>?

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

        // The service extension prefetched the transcript into the shared cache on push arrival, so
        // the common path renders instantly with no gRPC connection resident in this extension.
        if let cached = NotificationPreviewCache.read(for: conversationID), !cached.isEmpty {
            render(cached)
            Self.logger.info("Notification transcript rendered from cache", metadata: [
                "availableMemoryMB": "\(os_proc_available_memory() / (1024 * 1024))",
            ])
        } else {
            // Cache miss (prefetch failed or hadn't finished) — fetch live over a transient connection.
            loadTask = Task { @MainActor in await loadLive() }
        }
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
                let selfUserID
            else {
                completion(.dismiss)
                return
            }

            let text = textResponse.userText
            // A cache-miss live fetch (if any) is superseded by this reply's own fetch — cancel it so
            // the two don't interleave their renders.
            loadTask?.cancel()
            replyTask?.cancel()
            replyTask = Task { @MainActor in
                do {
                    // A transient connection: opened for the send + refresh, torn down after — no
                    // connection sits resident in this extension's memory budget.
                    let client = try ChatNotificationClient()
                    // One client message id across retries so the server dedups — a fresh id per attempt
                    // would post duplicate messages.
                    let clientMessageID = UUID()
                    _ = try await Task.retry(maxAttempts: 3, delay: .milliseconds(400)) {
                        try await client.sendMessage(owner: ownerKeyPair, conversationID: conversationID, text: text, clientMessageID: clientMessageID)
                    }
                    // Re-fetch so the sent message appears, and refresh the cache for the next open.
                    let messages = try await client.getMessages(
                        owner: ownerKeyPair,
                        conversationID: conversationID,
                        limit: NotificationPreviewCache.previewLimit
                    )
                    // An empty post-send read (lost the read-after-write race) would otherwise blank the
                    // transcript and overwrite the good cache with []; keep what's already shown instead.
                    if !messages.isEmpty {
                        await renderAndCache(messages, conversationID: conversationID, selfUserID: selfUserID, client: client)
                    }
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

    /// Fetches the recent transcript over a transient connection when the prefetch cache missed.
    /// Best-effort: a failure shows a status hint rather than a blank panel.
    @MainActor
    private func loadLive() async {
        guard let conversationID, let ownerKeyPair, let selfUserID else { return }
        do {
            let client = try ChatNotificationClient()
            let messages = try await client.getMessages(
                owner: ownerKeyPair,
                conversationID: conversationID,
                limit: NotificationPreviewCache.previewLimit,
                retryingEmpty: true
            )
            if messages.isEmpty {
                showStatusLabel("No messages")
            } else {
                await renderAndCache(messages, conversationID: conversationID, selfUserID: selfUserID, client: client)
            }
        } catch {
            showStatusLabel("Couldn't load messages")
        }
    }

    /// Renders the rows immediately (currency-code fallback for any unbranded mint), resolves token
    /// names + icons over `client`, re-renders so they swap in, and refreshes the shared cache so a
    /// re-open is instant. The bubble is never gated on the branding round-trip.
    @MainActor
    private func renderAndCache(
        _ messages: [ConversationMessage],
        conversationID: ConversationID,
        selfUserID: UserID,
        client: ChatNotificationClient
    ) async {
        func items(_ branding: [PublicKey: MintBrandingInfo]) -> [ChatItem] {
            ChatItem.preview(
                from: messages,
                selfUserID: selfUserID,
                limit: NotificationPreviewCache.previewLimit,
                mintBranding: branding
            )
        }
        render(items([:]))
        let branding: [PublicKey: MintBrandingInfo]
        do {
            branding = try await client.resolveMintBranding(in: messages)
        } catch {
            Self.logger.error("Failed to resolve mint metadata", metadata: ["error": "\(error)"])
            branding = [:]
        }
        let resolved = items(branding)
        render(resolved)
        NotificationPreviewCache.write(resolved, for: conversationID)
    }

    private func render(_ items: [ChatItem]) {
        clearStatusLabel()
        transcript.rootView = NotificationTranscriptView(items: items)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loadTask?.cancel()
        loadTask = nil
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
