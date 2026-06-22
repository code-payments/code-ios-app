//
//  NotificationViewController.swift
//  NotificationContent
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
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

    /// Preserved across didReceive calls so reply can reuse them.
    private var conversationID: ConversationID?
    private var ownerKeyPair: KeyPair?
    private var selfUserID: UserID?

    // MARK: - Lifecycle -

    override func viewDidLoad() {
        super.viewDidLoad()
        FontBook.registerApplicationFonts()
        setupCollectionView()
    }

    // MARK: - UNNotificationContentExtension -

    func didReceive(_ notification: UNNotification) {
        guard let conversationID = NotificationPayload.chatConversationID(
            from: notification.request.content.userInfo
        ) else {
            // Not a chat push or no payload — leave the default banner.
            return
        }
        guard let account = OwnerKeyStore.loadOwnerAccount() else {
            // Not logged in — leave the default banner.
            return
        }
        self.conversationID = conversationID
        self.ownerKeyPair = account.keyAccount.owner
        self.selfUserID = account.userID

        apply(.loading)

        Task { @MainActor in
            do {
                let client = ChatNotificationClient()
                let messages = try await client.getMessages(
                    owner: account.keyAccount.owner,
                    conversationID: conversationID,
                    limit: 3
                )
                if messages.isEmpty {
                    apply(.empty)
                } else {
                    let chatItems = ChatItem.preview(from: messages, selfUserID: account.userID, limit: 3)
                    apply(.loaded(chatItems))
                }
            } catch {
                apply(.error("Couldn't load messages"))
            }
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
                let ownerKeyPair
            else {
                completion(.dismiss)
                return
            }

            let text = textResponse.userText
            Task { @MainActor in
                do {
                    let client = ChatNotificationClient()
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
                    showSendError()
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
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.backgroundColor = .clear
        config.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout.list(using: config)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.register(ChatMessageCell.self, forCellWithReuseIdentifier: ChatMessageCell.reuseIdentifier)

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

        case .loaded(let chatItems):
            clearStatusLabel()
            items = chatItems
            collectionView.reloadData()
            updatePreferredContentSize()

        case .empty:
            clearStatusLabel()
            items = []
            collectionView.reloadData()
            updatePreferredContentSize()

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
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        statusLabel = label
        preferredContentSize = CGSize(width: view.bounds.width, height: 44)
    }

    private func clearStatusLabel() {
        statusLabel?.removeFromSuperview()
        statusLabel = nil
    }

    private func showSendError() {
        showStatusLabel("Couldn't send message")
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
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChatMessageCell.reuseIdentifier,
            for: indexPath
        ) as! ChatMessageCell  // swiftlint:disable:this force_cast

        let item = items[indexPath.item]
        switch item {
        case .message(let message):
            let maxWidth = collectionView.bounds.width * 0.78
            cell.configure(with: message, maxWidth: maxWidth)
        case .dateSeparator, .receipt:
            // Preview only shows message bubbles — separators not expected for ≤3 messages.
            break
        }
        return cell
    }
}
