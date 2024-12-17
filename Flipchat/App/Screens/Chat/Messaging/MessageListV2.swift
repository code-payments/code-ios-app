//
//  MessageListV2.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import SwiftUI
import FlipchatServices
import CodeUI

struct MessageListV2: UIViewRepresentable {
    
    let userID: UserID
    let hostID: UserID
    let chatID: ChatID
    let unread: UnreadDescription?
    let messages: [MessageRow]
    let scroll: Binding<ScrollConfiguration?>
    let action: (MessageAction) -> Void
    let loadMore: () -> Void
    
    init(userID: UserID, hostID: UserID, chatID: ChatID, unread: UnreadDescription? = nil, messages: [MessageRow], scroll: Binding<ScrollConfiguration?>, action: @escaping (MessageAction) -> Void, loadMore: @escaping () -> Void) {
        self.userID   = userID
        self.hostID   = hostID
        self.chatID   = chatID
        self.unread   = unread
        self.messages = messages
        self.scroll   = scroll
        self.action   = action
        self.loadMore = loadMore
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            list: self,
            userID: userID,
            hostID: hostID,
            chatID: chatID,
            action: action
        )
    }

    func makeUIView(context: Context) -> UIView {
        let bounds = UIScreen.main.bounds
        
        let container = UIView(frame: bounds)
        
        let tableView = UITableView(frame: bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource          = context.coordinator
        tableView.delegate            = context.coordinator
        tableView.separatorStyle      = .none
        tableView.backgroundColor     = UIColor.systemBackground
        tableView.allowsSelection     = false
        tableView.estimatedRowHeight  = UITableView.automaticDimension
        tableView.backgroundColor     = .clear
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset        = .init(top: 10, left: 0, bottom: 15, right: 0)
        tableView.tag                 = .tableViewTag
        context.coordinator.tableView = tableView
        
        let scrollButton = UIButton(type: .custom)
        scrollButton.setImage(UIImage.asset(.scrollBottom), for: .normal)
        scrollButton.translatesAutoresizingMaskIntoConstraints = false
        scrollButton.addTarget(context.coordinator, action: #selector(Coordinator.scrollToBottom), for: .touchUpInside)
        scrollButton.tag = .scrollButton
        
        container.addSubview(tableView)
        container.addSubview(scrollButton)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: container.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            scrollButton.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            scrollButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollButton.widthAnchor.constraint(equalToConstant: 40),
            scrollButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        let tableView = container.viewWithTag(.tableViewTag) as! UITableView
        let scrollButton = container.viewWithTag(.scrollButton) as! UIButton
        
        context.coordinator.unreadDescription = unread
        context.coordinator.tableView = tableView
        context.coordinator.scrollButton = scrollButton
        context.coordinator.update(newMessages: messages)
        
        if let configuration = scroll.wrappedValue {
            context.coordinator.scrollTo(configuration: configuration)
            Task { // Have to modify when not updating
                scroll.wrappedValue = nil
            }
        }
    }
}

private extension Int {
    static let tableViewTag = 0xE73E8995
    static let scrollButton = 0xE73E8996
}

// MARK: - Coordinator -

extension MessageListV2 {
    class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        
        typealias Action = (MessageAction) -> Void
        
        var unreadDescription: UnreadDescription?
        
        private let list: MessageListV2
        private let userID: UserID
        private let hostID: UserID
        private let chatID: ChatID
        private let action: Action
        
        private var messages: [MessageDescription] = []
        
        fileprivate weak var tableView: UITableView!
        fileprivate weak var scrollButton: UIButton!
        
        private let defaultMemberName = "Member"

        init(list: MessageListV2, userID: UserID, hostID: UserID, chatID: ChatID, action: @escaping (MessageAction) -> Void) {
            self.list = list
            self.userID = userID
            self.hostID = hostID
            self.chatID = chatID
            self.action = action
        }

        func update(newMessages: [MessageRow]) {
            var container: [MessageDescription] = []
            var unreadIndex: Int?
            
            for dateGroup in newMessages.groupByDay(userID: userID) {
                
                // Date
                container.append(
                    .init(
                        kind: .date(dateGroup.date),
                        content: dateGroup.date.formattedRelatively()
                    )
                )
                
                for messageContainer in dateGroup.messages {
                    
                    let message = messageContainer.row.message
                    let isReceived = message.senderID != userID.uuid
                    
                    switch message.contentType {
                    case .text, .reply:
                        container.append(
                            .init(
                                kind: .message(ID(uuid: message.serverID), isReceived, messageContainer.row, messageContainer.location),
                                content: message.content
                            )
                        )
                        
                    case .announcement:
                        container.append(
                            .init(
                                kind: .announcement(ID(uuid: message.serverID)),
                                content: message.content
                            )
                        )
                        
                    case .reaction, .unknown:
                        break
                    }
                    
                    // If unread description is present, we'll augment the list of
                    // messages to include an unread banner as a 'message' row. The
                    // pointer is to the last seen message so we have to insert the
                    // banner after the message itself.
                    if let unreadDescription, message.serverID == unreadDescription.messageID, unreadDescription.unread > 0 {
                        
                        // Index of this message in container
                        unreadIndex = container.count
                        
                        let count = unreadDescription.unread
                        container.append(
                            .init(
                                kind: .unread,
                                content: "\(count) Unread Message\(count == 1 ? "" : "s")"
                            )
                        )
                    }
                }
            }
            
            let isEmpty = messages.isEmpty
            
            if let lastItem = container.last, lastItem.kind == .unread {
                print("Removed unread banner, it's the last message")
                unreadIndex = nil
                container.removeLast()
            }
            
            messages = container
            tableView.reloadData()
            
            if isEmpty {
                if let unreadIndex {
                    // Show one message from previously seen
                    // and then banner followed by all new
                    let adjustedIndex = max(unreadIndex - 1, 0)
                    scrollTo(
                        configuration: .init(
                            destination: .row(adjustedIndex),
                            position: .top,
                            animated: false
                        )
                    )
                } else {
                    scrollTo(
                        configuration: .init(
                            destination: .bottom,
                            animated: false
                        )
                    )
                }
            }
        }
        
        @objc fileprivate func scrollToBottom() {
            scrollTo(configuration: .init(
                destination: .bottom,
                position: .bottom,
                delay: 0,
                animated: true
            ))
        }
        
        func scrollTo(messageID: UUID) {
            let index = messages.firstIndex {
                if case .message(let id, _, _, _) = $0.kind {
                    return messageID == id.uuid
                }
                return false
            }
            
            // Message not found
            guard let index else {
                return
            }
            
            scrollTo(
                configuration: .init(
                    destination: .row(index),
                    position: .top,
                    delay: 0,
                    animated: true
                )
            )
        }
        
        func scrollTo(configuration: ScrollConfiguration) {
            let indexPath: IndexPath
            switch configuration.destination {
            case .bottom:
                indexPath = IndexPath(row: messages.count - 1, section: 0)
            case .row(let row):
                indexPath = IndexPath(row: row, section: 0)
            }
            
            Task {
                if configuration.delay > 0 {
                    try await Task.delay(milliseconds: configuration.delay)
                }
                
                if configuration.animated {
                    UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveEaseInOut) { [tableView] in
                        tableView?.scrollToRow(
                            at: indexPath,
                            at: configuration.position,
                            animated: true
                        )
                    }
                    
                } else {
                    tableView.scrollToRow(
                        at: indexPath,
                        at: configuration.position,
                        animated: false
                    )
                }
            }
        }
        
        // MARK: - ScrollView -
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let height        = scrollView.frame.height
            let contentHeight = scrollView.contentSize.height
            let offsetY       = scrollView.contentOffset.y
            let threshold     = contentHeight - height / 2
            
            if offsetY >= threshold - height {
                UIView.animate(withDuration: 0.15) {
                    self.scrollButton?.alpha = 0.0
                }
            } else {
                UIView.animate(withDuration: 0.15) {
                    self.scrollButton?.alpha = 1.0
                }
            }
        }
        
        // MARK: - UITableViewDataSource -
        
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            messages.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MessageTableCell
            
            let message = messages[indexPath.row]
            let width = message.messageWidth(in: tableView.frame.size).width
            
            cell.backgroundColor = .clear
            cell.swipeEnabled    = message.kind.messageRow != nil
            cell.onSwipeToReply  = { [weak self] in
                self?.action(.reply(message.kind.messageRow!))
            }
            
            cell.contentConfiguration = UIHostingConfiguration {
                let row = row(
                    for: message,
                    userID: userID,
                    hostID: hostID,
                    action: action
                )
                
                MessageRowView(kind: message.kind, width: width) { row }
            }
            .margins(.vertical, 2)
            .margins(.horizontal, 0)

            // Load more when reaching the last cell
//            if indexPath.row == messages.count - 1 {
//                list.loadMore()
//            }

            return cell
        }

        // MARK: - UITableViewDelegate -

        func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
            UITableView.automaticDimension
        }
        
        @ViewBuilder
        private func row(for description: MessageDescription, userID: UserID, hostID: UserID, action: @escaping Action) -> some View {
            switch description.kind {
            case .date(let date):
                MessageTitle(text: date.formattedRelatively())
                
            case .message(_, let isReceived, let row, let location):
                let message = row.message
                let isFromSelf = message.senderID == userID.uuid
                let displayName = row.member.displayName ?? defaultMemberName
                
                MessageText(
                    state: message.state,
                    name: displayName,
                    avatarData: message.senderID?.data ?? Data([0, 0, 0, 0]),
                    text: description.content,
                    date: message.date,
                    isReceived: isReceived,
                    isHost: message.senderID == hostID.uuid,
                    replyingTo: replyingTo(for: row, action: action),
                    location: location
                ) {
                    Button {
                        Task {
                            action(.reply(row))
                        }
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.backward.fill")
                    }
                    
                    Button {
                        action(.copy(description.content))
                    } label: {
                        Label("Copy Message", systemImage: "doc.on.doc")
                    }
                    
                    Divider()
                    
                    if let senderID = message.senderID, senderID != userID.uuid {
                        Button(role: .destructive) {
                            action(.reportMessage(UserID(data: senderID.data), MessageID(uuid: message.serverID)))
                        } label: {
                            Label("Report", systemImage: "exclamationmark.shield")
                        }
                    }
                    
                    // Only if the current user is a host
                    if !isFromSelf, userID == hostID, let senderID = message.senderID {
                        Button(role: .destructive) {
                            action(.muteUser(displayName, UserID(data: senderID.data), self.chatID))
                        } label: {
                            Label("Mute", systemImage: "speaker.slash")
                        }
                    }
                }
                
            case .announcement:
                MessageAnnouncement(text: description.content)
                
            case .unread:
                MessageUnread(text: description.content)
            }
        }
        
        func replyingTo(for row: MessageRow, action: @escaping Action) -> ReplyingTo? {
            guard
                let referenceID = row.referenceID,
                let reference = row.reference
            else {
                return nil
            }
            
            return .init(
                name: reference.displayName ?? defaultMemberName,
                content: reference.content,
                action: { [weak self] in
                    self?.scrollTo(messageID: referenceID)
                }
            )
        }
    }
}

// MARK: - Row -

private struct MessageRowView<Content>: View where Content: View {
    
    private let kind: MessageDescription.Kind
    private let width: CGFloat
    private let content: () -> Content
    
    private var vAlignment: HorizontalAlignment {
        switch kind {
        case .date:
            return .center
        case .message(_, let isReceived, _, _):
            return isReceived ? .leading : .trailing
        case .announcement, .unread:
            return .center
        }
    }
    
    private var alignment: Alignment {
        switch kind {
        case .date:
            return .top
        case .message(_, let isReceived, _, _):
            return isReceived ? .leading : .trailing
        case .announcement, .unread:
            return .bottom
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch kind {
        case .date, .message, .announcement:
            return 20
        case .unread:
            return 0
        }
    }
    
    init(kind: MessageDescription.Kind, width: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.kind = kind
        self.width = width
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: vAlignment) {
            HStack {
                switch kind {
                case .date, .announcement, .unread:
                    content()
                    
                case .message(_, let isReceived, _, _):
                    if isReceived {
                        content()
                        Spacer()
                    } else {
                        Spacer()
                        content()
                    }
                }
            }
            .frame(maxWidth: width, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, horizontalPadding)
    }
}

// MARK: - Types -

struct ScrollConfiguration {
    
    var destination: Destination
    var position: UITableView.ScrollPosition
    var delay: Int // milliseconds
    var animated: Bool
    
    init(destination: Destination, position: UITableView.ScrollPosition = .middle, delay: Int = 25, animated: Bool) {
        self.destination = destination
        self.position = position
        self.delay = delay
        self.animated = animated
    }
    
    enum Destination {
        case bottom
        case row(Int)
    }
}

struct UnreadDescription {
    var messageID: UUID
    var unread: Int
}
