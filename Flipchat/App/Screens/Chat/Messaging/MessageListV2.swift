//
//  MessageListV2.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import SwiftUI
import FlipchatServices

struct MessageListV2: UIViewRepresentable {
    
    let userID: UserID
    let hostID: UserID
    let chatID: ChatID
    let messages: [MessageRow]
    let action: (MessageAction) -> Void
    let loadMore: () -> Void
    
    init(userID: UserID, hostID: UserID, chatID: ChatID, messages: [MessageRow], action: @escaping (MessageAction) -> Void, loadMore: @escaping () -> Void) {
        self.userID   = userID
        self.hostID   = hostID
        self.chatID   = chatID
        self.messages = messages
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

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: UIScreen.main.bounds, style: .plain)
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        
        tableView.dataSource          = context.coordinator
        tableView.delegate            = context.coordinator
        tableView.separatorStyle      = .none
        tableView.backgroundColor     = UIColor.systemBackground
        tableView.allowsSelection     = false
        tableView.estimatedRowHeight  = UITableView.automaticDimension
        tableView.backgroundColor     = .clear
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset        = .init(top: 10, left: 0, bottom: 15, right: 0)
        
        context.coordinator.tableView = tableView
        
        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.tableView = tableView
        context.coordinator.update(newMessages: messages)
    }
}

// MARK: - Coordinator -

extension MessageListV2 {
    class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        
        typealias Action = (MessageAction) -> Void
        
        private let list: MessageListV2
        private let userID: UserID
        private let hostID: UserID
        private let chatID: ChatID
        private let action: Action
        
        private var messages: [MessageDescription] = []
        
        fileprivate weak var tableView: UITableView!

        init(list: MessageListV2, userID: UserID, hostID: UserID, chatID: ChatID, action: @escaping (MessageAction) -> Void) {
            self.list = list
            self.userID = userID
            self.hostID = hostID
            self.chatID = chatID
            self.action = action
        }

        func update(newMessages: [MessageRow]) {
            var container: [MessageDescription] = []
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
                }
            }
            
            let isEmpty = messages.isEmpty
            
            messages = container
            tableView.reloadData()
            
            if isEmpty {
                Task {
                    tableView.scrollToRow(at: IndexPath(row: container.count - 1, section: 0), at: .bottom, animated: false)
                }
            }
        }
        
        // MARK: - UITableViewDataSource -
        
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            messages.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            
            cell.backgroundColor = .clear
            
            let message = messages[indexPath.row]
            let width = message.messageWidth(in: tableView.frame.size).width
            
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
                let displayName = row.member.displayName ?? "Member"
                
                MessageText(
                    state: message.state,
                    name: displayName,
                    avatarData: message.senderID?.data ?? Data([0, 0, 0, 0]),
                    text: description.content,
                    date: message.date,
                    isReceived: isReceived,
                    isHost: message.senderID == hostID.uuid,
                    location: location
                ) {
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
            }
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
        case .announcement:
            return .center
        }
    }
    
    private var alignment: Alignment {
        switch kind {
        case .date:
            return .top
        case .message(_, let isReceived, _, _):
            return isReceived ? .leading : .trailing
        case .announcement:
            return .bottom
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
                case .date, .announcement:
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
    }
}
