//
//  MessageListV2.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import SwiftUI
import FlipchatServices
import CodeUI

typealias MessageActionHandler = (MessageAction) -> Void

struct MessagesListController: UIViewControllerRepresentable {
    
    let chatController: ChatController
    let userID: UserID
    let chatID: ChatID
    let scroll: Binding<ScrollConfiguration?>
    let action: MessageActionHandler
    let loadMore: () async throws -> Void

    func makeUIViewController(context: Context) -> _MessagesListController {
        let controller = _MessagesListController(
            chatController: chatController,
            userID: userID,
            chatID: chatID,
            scroll: scroll,
            action: action,
            loadMore: loadMore
        )
        
        return controller
    }

    func updateUIViewController(_ controller: _MessagesListController, context: Context) {
        controller.set(scroll: scroll)
    }
}

@MainActor
class _MessagesListController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    let chatController: ChatController
    let userID: UserID
    let chatID: ChatID
    let action: MessageActionHandler
    let loadMore: () async throws -> Void
    
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let scrollButton = UIButton(type: .custom)
    
    private let defaultMemberName = "Member"
    
    private var isAroundBottom: Bool = false
    private var isLoadingMore: Bool = false
    
    private var state: ConversationState!
    
    private var messages: [MessageDescription]
    private var scroll: Binding<ScrollConfiguration?>?
    private var unreadBannerIndex: Int?
    
    private var stream: StreamMessagesReference?
    
    // MARK: - Init -
    
    init(
        chatController: ChatController,
        userID: UserID,
        chatID: ChatID,
        scroll: Binding<ScrollConfiguration?>?,
        action: @escaping MessageActionHandler,
        loadMore: @escaping () async throws -> Void
    ) {
        self.chatController = chatController
        self.userID         = userID
        self.chatID         = chatID
        self.messages       = []
        self.scroll         = scroll
        self.action         = action
        self.loadMore       = loadMore
        
        super.init(nibName: nil, bundle: nil)
        
        self.state = ConversationState(
            userID: userID,
            chatID: chatID,
            chatController: chatController,
            didLoad: { [weak self] rows, unread in
                self?.processRowsIntoDescriptions(rows: rows, unread: unread)
            }
        )
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    deinit {
        DispatchQueue.main.async { [stream] in
            trace(.warning, components: "Destroying conversation stream...")
            stream?.destroy()
        }
    }
    
    private func setupViews() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: "cell")
        tableView.separatorStyle      = .none
        tableView.backgroundColor     = .clear
        tableView.allowsSelection     = false
        tableView.estimatedRowHeight  = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactive
        tableView.contentInset        = .init(
            top: 10,
            left: 0,
            bottom: 15,
            right: 0
        )
        
        view.addSubview(tableView)
        
        scrollButton.translatesAutoresizingMaskIntoConstraints = false
        scrollButton.setImage(UIImage.asset(.scrollBottom), for: .normal)
        scrollButton.addTarget(self, action: #selector(animateToBottom), for: .touchUpInside)
        view.addSubview(scrollButton)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            scrollButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            scrollButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollButton.widthAnchor.constraint(equalToConstant: 40),
            scrollButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }
    
    // MARK: - Did Load -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupViews()
        
        scrollToInitialPosition()
        
        Task {
            try? await syncChatAndMembers()
            try? await advanceReadPointer()
            
            startStream()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(databaseDidChange(notification:)), name: .databaseDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillEnterForeground(notification:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground(notification:)),  name: UIApplication.didEnterBackgroundNotification,  object: nil)
    }
    
    // MARK: - Database Updates -
    
    @objc private func databaseDidChange(notification: Notification) {
        state.loadFromDatabase()
    }
    
    @objc private func applicationWillEnterForeground(notification: Notification) {
        startStream()
    }
    
    @objc private func applicationDidEnterBackground(notification: Notification) {
        destroyStream()
    }
    
    // MARK: - Requests -
    
    private func syncChatAndMembers() async throws {
        try await chatController.syncChatAndMembers(for: chatID)
    }
    
    private func advanceReadPointer() async throws {
        try await chatController.advanceReadPointerToLatest(for: chatID)
    }
    
    // MARK: - Streams -
    
    func startStream() {
        destroyStream()
        
        guard let room = state.room else {
            return
        }
        
        let messageID: MessageID?
        if let lastMessage = room.lastMessage {
            messageID = MessageID(uuid: lastMessage.serverID)
        } else {
            messageID = nil
        }
        
        stream = chatController.streamMessages(chatID: chatID, messageID: messageID) { [weak self] result in
            switch result {
            case .success(let messages):
                self?.streamMessages(messages: messages)

            case .failure:
                self?.destroyStream()
            }
        }
    }
    
    private func streamMessages(messages: [Chat.Message]) {
        Task {
            try await chatController.receiveMessages(messages: messages, for: chatID)
            try await advanceReadPointer()
        }
    }
    
    func destroyStream() {
        trace(.warning, components: "Destroying conversation stream...")
        stream?.destroy()
    }
    
    // MARK: - Setters -
    
    func set(scroll: Binding<ScrollConfiguration?>?) {
        self.scroll = scroll
        
        consumeScroll()
    }
    
    private func consumeScroll() {
        guard let scroll, let config = scroll.wrappedValue else {
            return
        }
        
        scrollTo(configuration: config)
        DispatchQueue.main.async {
            scroll.wrappedValue = nil
        }
    }
    
    private func processRowsIntoDescriptions(rows: [MessageRow]?, unread: UnreadDescription?) {
        guard let rows else {
            return
        }
        
        let (messages, unreadIndex) = rows.messageDescriptions(userID: userID, unread: unread)
        
        // Determine if we should scroll to the bottom
        let lastNewMessageID = messages.last?.kind.messageRow?.message.serverID
        let lastCurrentMessageID = self.messages.last?.kind.messageRow?.message.serverID
        var shouldScroll = false
        if
            let lastNewMessageID,
            let lastCurrentMessageID,
            lastNewMessageID > lastCurrentMessageID, // Only scroll if there's newer messages
            isAroundBottom, // Only scroll if we're close to the bottom
            !self.messages.isEmpty // Only scroll if we're updating not initializing the list
        {
            shouldScroll = true
        }
        
        self.messages = messages
        self.unreadBannerIndex = unreadIndex
        
        if isViewLoaded {
            reload()
            
            // Scroll after the table view has reloaded
            if shouldScroll {
                animateToBottom()
            }
        }
    }
    
    // MARK: - Scrolling -
    
    private func reload() {
        tableView.reloadData()
    }
    
    private func scrollToInitialPosition() {
        if let unreadBannerIndex {
            // Show one message from previously seen
            // and then banner followed by all new
            let adjustedIndex = max(unreadBannerIndex - 1, 0)
            scrollTo(
                configuration: .init(
                    destination: .row(adjustedIndex),
                    position: .top,
                    delay: 0,
                    animated: false
                )
            )
        } else {
            scrollTo(
                configuration: .init(
                    destination: .bottom,
                    delay: 0,
                    animated: false
                )
            )
        }
    }
    
    @objc fileprivate func animateToBottom() {
        scrollTo(configuration: .init(
            destination: .bottom,
            position: .bottom,
            delay: 0,
            animated: true
        ))
    }
    
    private func scrollTo(messageID: UUID) {
        let index = messages.firstIndex {
            if case .message(let id, _, _, _, _) = $0.kind {
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
    
    private func scrollTo(configuration: ScrollConfiguration) {
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
            
            print("[MessageListV2] Scrolling to index: \(indexPath.row), total: \(messages.count - 1)")
            
            tableView.scrollToRow(
                at: indexPath,
                at: configuration.position,
                animated: configuration.animated
            )
        }
    }
    
    // MARK: - ScrollView -
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let height        = scrollView.frame.height
        let contentHeight = scrollView.contentSize.height
        let offsetY       = scrollView.contentOffset.y - scrollView.contentInset.bottom - scrollView.safeAreaInsets.bottom
        let threshold     = contentHeight - height - height / 2
        
        if offsetY >= threshold {
            isAroundBottom = true
            setScrollButton(visible: !isAroundBottom)
        } else {
            isAroundBottom = false
            setScrollButton(visible: !isAroundBottom)
        }
        
//        if offsetY < height, !isLoadingMore {
//            isLoadingMore = true
//            Task {
//                try? await loadMore()
//                try await Task.delay(milliseconds: 1000)
//                isLoadingMore = false
//            }
//        }
    }
    
    private func setScrollButton(visible: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.scrollButton.alpha = self.isAroundBottom ? 0.0 : 1.0
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
                hostID: UserID(uuid: state.room.room.ownerUserID),
                action: action
            )
            
            MessageRowView(kind: message.kind, width: width) { row }
        }
        .minSize(width: 0, height: 20)
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
    private func row(for description: MessageDescription, userID: UserID, hostID: UserID, action: @escaping MessageActionHandler) -> some View {
        switch description.kind {
        case .date(let date):
            MessageTitle(text: date.formattedRelatively())
            
        case .message(_, let isReceived, let row, let location, let deletionState):
            let message = row.message
            let isFromSelf = message.senderID == userID.uuid
            let displayName = row.member.displayName ?? defaultMemberName
            let chatID = chatID
            
            MessageText(
                state: message.state,
                name: displayName,
                avatarData: message.senderID?.data ?? Data([0, 0, 0, 0]),
                text: description.content,
                date: message.date,
                isReceived: isReceived,
                isHost: message.senderID == hostID.uuid,
                isBlocked: row.member.isBlocked == true,
                deletionState: deletionState,
                replyingTo: replyingTo(for: row, action: action),
                location: location,
                action: { [weak self] messageAction in
                    self?.action(messageAction)
                }
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
                
                // Allow deletes for self messages or if room host is deleting a message
                if let senderID = message.senderID, senderID == userID.uuid, userID == hostID {
                    Button(role: .destructive) {
                        action(.deleteMessage(MessageID(uuid: message.serverID), chatID))
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
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
                        action(.muteUser(displayName, UserID(data: senderID.data), chatID))
                    } label: {
                        Label("Mute", systemImage: "speaker.slash")
                    }
                }
                
                // Only if the sender isn't self (can't block self)
                if let senderID = message.senderID, senderID != userID.uuid {
                    Button(role: .destructive) {
                        action(.setUserBlocked(displayName, UserID(data: senderID.data), chatID, !(row.member.isBlocked == true)))
                    } label: {
                        if row.member.isBlocked == true {
                            Label("Unblock", systemImage: "person.slash")
                        } else {
                            Label("Block", systemImage: "person.slash")
                        }
                    }
                }
            }
            
        case .announcement:
            MessageAnnouncement(text: description.content)
            
        case .unread:
            MessageUnread(text: description.content)
        }
    }
    
    func replyingTo(for row: MessageRow, action: @escaping MessageActionHandler) -> ReplyingTo? {
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

// MARK: - State -

@MainActor
class ConversationState {
    
    private(set) var room: RoomDescription!
    private(set) var pointer: MessagePointer?
    private(set) var rows: [MessageRow] = []
    
    private let userID: UserID
    private let chatID: ChatID
    private let chatController: ChatController
    private let didLoad: ([MessageRow]?, UnreadDescription?) -> Void
    
    init(userID: UserID, chatID: ChatID, chatController: ChatController, didLoad: @escaping ([MessageRow]?, UnreadDescription?) -> Void) {
        self.userID = userID
        self.chatID = chatID
        self.chatController = chatController
        self.didLoad = didLoad
        
        pointer = try? chatController.getPointer(userID: userID, chatID: chatID)
        loadFromDatabase()
        
        print("Initialized state.")
    }
    
    deinit {
        print("Deinitialized state.")
    }
    
    func loadFromDatabase() {
        let start = Date.now
        room = try? chatController.getRoom(chatID: chatID)
        rows = (try? chatController.getMessages(chatID: chatID, pageSize: 1024)) ?? []
        print("[ConversationState] Loaded in \(Date.now.formattedMilliseconds(from: start))")
        didLoad(rows, unreadDescription)
    }
    
    var unreadDescription: UnreadDescription? {
        if let pointer {
            return UnreadDescription(
                messageID: pointer.messageID,
                unread: pointer.newUnreads
            )
        }
        return nil
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
        case .message(_, let isReceived, _, _, _):
            return isReceived ? .leading : .trailing
        case .announcement, .unread:
            return .center
        }
    }
    
    private var alignment: Alignment {
        switch kind {
        case .date:
            return .top
        case .message(_, let isReceived, _, _, _):
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
                    
                case .message(_, let isReceived, _, _, _):
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

extension Array where Element == MessageRow {
    func messageDescriptions(userID: UserID, unread: UnreadDescription?) -> (descriptions: [MessageDescription], unreadIndex: Int?) {
        var container: [MessageDescription] = []
        var unreadIndex: Int?
        
        // 1. On first pass we index all deleted IDs
        var deletedIDs: [UUID: UserID?] = [:]
        for description in self {
            guard
                description.message.contentType == .deleteMessage,
                let referenceID = description.referenceID
            else {
                continue
            }
            
            deletedIDs[referenceID] = ID(uuid: description.message.senderID)
        }
        
        // 2. Second pass is to remove the meta messages
        // from the main list that will go into date groups
        let filteredMessages = filter {
            switch $0.message.contentType {
            case .text, .announcement, .reply:
                return true
            case .reaction, .tip, .deleteMessage, .unknown:
                return false
            }
        }
        
        // 3. Third pass is to group messages by date
        // and generate the descriptions we'll use for
        // rendering the list of messages
        for dateGroup in filteredMessages.groupByDay(userID: userID) {
            
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
                
                var deletionState: MessageDeletion?
                if let deletionUser = deletedIDs[message.serverID] {
                    deletionState = MessageDeletion(
                        senderID: deletionUser?.uuid,
                        isSelf: deletionUser == userID
                    )
                }
                
                switch message.contentType {
                case .text, .reply:
                    container.append(
                        .init(
                            kind: .message(
                                ID(uuid: message.serverID),
                                isReceived,
                                messageContainer.row,
                                messageContainer.location,
                                deletionState
                            ),
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
                    
                case .reaction, .tip, .deleteMessage, .unknown:
                    break
                }
                
                // If unread description is present, we'll augment the list of
                // messages to include an unread banner as a 'message' row. The
                // pointer is to the last seen message so we have to insert the
                // banner after the message itself.
                if let unread, message.serverID == unread.messageID, unread.unread > 0 {
                    
                    // Index of this message in container
                    unreadIndex = container.count
                    
                    let count = unread.unread
                    container.append(
                        .init(
                            kind: .unread,
                            content: "\(count) Unread Message\(count == 1 ? "" : "s")"
                        )
                    )
                }
            }
        }
        
        if let lastItem = container.last, lastItem.kind == .unread {
            print("Removed unread banner, it's the last message")
            unreadIndex = nil
            container.removeLast()
        }
        
        return (container, unreadIndex)
    }
}
