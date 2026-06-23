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

    // MARK: - State -

    private enum ViewState {
        case loading
        case loaded([ChatItem])
        case empty
        case error(String)
    }

    // MARK: - Properties -

    private var collectionView: UICollectionView!
    private var items: [ChatItem] = []
    private var statusLabel: UILabel?

    /// Mirrors the app's "background" color asset (display-P3 25,25,26). Hardcoded
    /// because that asset lives in the app bundle, so `Color("background")` can't
    /// resolve it from this extension's bundle. The chat bubbles are white-on-dark
    /// by design, so the background must be this dark value or they render invisibly.
    private static let chatBackground = UIColor(
        displayP3Red: 25 / 255, green: 25 / 255, blue: 26 / 255, alpha: 1
    )

    /// Matches the real chat (ChatViewController).
    private static let maxBubbleWidthFraction: CGFloat = 0.78
    private static let interItemSpacing: CGFloat = 8

    /// How many recent messages the preview shows, and how often it re-checks the
    /// server for new ones while the notification stays expanded.
    private static let previewLimit = 5
    private static let pollInterval: TimeInterval = 2.5

    /// Single client shared across fetch and reply to avoid allocating multiple
    /// NIO event-loop groups per notification.
    private lazy var client = ChatNotificationClient()

    /// Preserved across didReceive calls so reply and polling can reuse them.
    private var conversationID: ConversationID?
    private var ownerKeyPair: KeyPair?
    private var selfUserID: UserID?

    /// Re-fetches recent messages while the notification is expanded so the
    /// counterparty's new messages appear live. Cancelled when the view goes away.
    private var pollTask: Task<Void, Never>?

    // MARK: - Lifecycle -

    override func viewDidLoad() {
        super.viewDidLoad()
        // The chat bubbles are white-on-dark by design; the app forces dark mode,
        // so the extension must too or the bubbles render invisibly on a light background.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Self.chatBackground
        FontBook.registerApplicationFonts()
        setupCollectionView()
    }

    // MARK: - UNNotificationContentExtension -

    func didReceive(_ notification: UNNotification) {
        guard let conversationID = NotificationPayload.chatConversationID(
            from: notification.request.content.userInfo
        ) else {
            // Not a chat push — leave the default banner.
            return
        }
        guard let account = OwnerKeyStore.loadOwnerAccount() else {
            // Not signed in — leave the default banner.
            return
        }
        self.conversationID = conversationID
        self.ownerKeyPair = account.keyAccount.owner
        self.selfUserID = account.userID

        apply(.loading)
        Task { @MainActor in await loadMessages() }
        startPolling()
    }

    /// Fetches the recent messages and renders them. Safe to call repeatedly (the poll
    /// does); a transient failure keeps the current content rather than clobbering it.
    @MainActor
    private func loadMessages() async {
        guard let conversationID, let ownerKeyPair, let selfUserID else { return }
        do {
            let messages = try await client.getMessages(
                owner: ownerKeyPair,
                conversationID: conversationID,
                limit: Self.previewLimit
            )
            if messages.isEmpty {
                if items.isEmpty { apply(.empty) }
            } else {
                apply(.loaded(ChatItem.preview(from: messages, selfUserID: selfUserID, limit: Self.previewLimit)))
            }
        } catch {
            if items.isEmpty { apply(.error("Couldn't load messages")) }
        }
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
                    let sent = try await client.sendMessage(
                        owner: ownerKeyPair,
                        conversationID: conversationID,
                        text: text
                    )
                    let sentItem = ChatItem.message(ChatMessage(
                        id: String(sent.id.value),
                        text: text,
                        sender: .me
                    ))
                    appendItem(sentItem)
                    completion(.doNotDismiss)
                } catch {
                    showStatusLabel("Couldn't send message")
                    completion(.doNotDismiss)
                }
            }

        case ChatNotificationCategory.sendCashActionID:
            completion(.dismissAndForwardAction)

        default:
            completion(.dismiss)
        }
    }

    // MARK: - Collection view setup -

    private func setupCollectionView() {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(44)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = Self.interItemSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        let layout = UICollectionViewCompositionalLayout(section: section)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = Self.chatBackground
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)
        collectionView.register(ChatCashCardCell.self, forCellWithReuseIdentifier: ChatCashCardCell.reuseIdentifier)

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - State application -

    @MainActor
    private func apply(_ state: ViewState) {
        switch state {
        case .loading:
            items = []
            collectionView.reloadData()
            showStatusLabel("Loading…")

        case .loaded(let chatItems):
            clearStatusLabel()
            items = chatItems
            collectionView.reloadData()
            updatePreferredContentSize()

        case .empty:
            items = []
            collectionView.reloadData()
            showStatusLabel("No messages")

        case .error(let message):
            items = []
            collectionView.reloadData()
            showStatusLabel(message)
        }
    }

    @MainActor
    private func appendItem(_ item: ChatItem) {
        clearStatusLabel()
        items.append(item)
        collectionView.reloadData()
        updatePreferredContentSize()
    }

    private func updatePreferredContentSize() {
        collectionView.layoutIfNeeded()
        let contentHeight = min(collectionView.contentSize.height, 320)
        preferredContentSize = CGSize(
            width: view.bounds.width,
            height: max(contentHeight, 44)
        )
    }

    // MARK: - Error UI -

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

// MARK: - UICollectionViewDataSource -

extension NotificationViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let item = items[indexPath.item]
        switch item {
        case .message(let message):
            switch message.content {
            case .text:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ChatMessageCell.reuseIdentifier,
                    for: indexPath
                ) as! ChatMessageCell  // swiftlint:disable:this force_cast
                cell.configure(with: message, maxWidth: collectionView.bounds.width * Self.maxBubbleWidthFraction)
                return cell
            case .cash:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: ChatCashCardCell.reuseIdentifier,
                    for: indexPath
                ) as! ChatCashCardCell  // swiftlint:disable:this force_cast
                cell.configure(with: message)
                return cell
            }
        case .dateSeparator, .receipt:
            // The preview mapping only emits .message rows.
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ChatMessageCell.reuseIdentifier,
                for: indexPath
            )
        }
    }
}
