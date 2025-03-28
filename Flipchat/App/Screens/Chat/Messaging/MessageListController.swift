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

protocol MessageListControllerDelegate {
    func messageListControllerKeyboardDismissed()
    func messageListControllerWillSendMessage(text: String) -> Bool
    func messageListControllerWillShowActionSheet(description: MessageActionDescription)
}

struct MessagesListController<BottomView, ReplyView>: UIViewControllerRepresentable where BottomView: View, ReplyView: View {
    
    var delegate: MessageListControllerDelegate?
    
    let chatController: ChatController
    let userID: UserID
    let chatID: ChatID
    let canType: Bool
    let bottomControlView: () -> BottomView
    let focus: Binding<FocusConfiguration?>
    let scroll: Binding<ScrollConfiguration?>
    let action: MessageActionHandler
    let showReply: Bool
    let replyView: () -> ReplyView
    
    init(delegate: MessageListControllerDelegate?, chatController: ChatController, userID: UserID, chatID: ChatID, canType: Bool, @ViewBuilder bottomControlView: @escaping () -> BottomView, focus: Binding<FocusConfiguration?>, scroll: Binding<ScrollConfiguration?>, action: @escaping MessageActionHandler, showReply: Bool, @ViewBuilder replyView: @escaping () -> ReplyView) {
        self.delegate = delegate
        self.chatController = chatController
        self.userID = userID
        self.chatID = chatID
        self.canType = canType
        self.bottomControlView = bottomControlView
        self.focus = focus
        self.scroll = scroll
        self.action = action
        self.showReply = showReply
        self.replyView = replyView
    }

    func makeUIViewController(context: Context) -> _MessagesListController<BottomView, ReplyView> {
        let controller = _MessagesListController(
            chatController: chatController,
            userID: userID,
            chatID: chatID,
            canType: canType,
            bottomControlView: bottomControlView,
            focus: focus,
            scroll: scroll,
            action: action,
            showReply: showReply,
            replyView: replyView
        )
        
        controller.delegate = delegate
        
        return controller
    }

    func updateUIViewController(_ controller: _MessagesListController<BottomView, ReplyView>, context: Context) {
        controller.delegate = delegate
        controller.bottomControlView = bottomControlView
        controller.replyView = replyView
        controller.canType = canType
        controller.showReply = showReply
        
        controller.set(scroll: scroll)
        controller.set(focus: focus)
    }
}

@MainActor
class _MessagesListController<BottomView, ReplyView>: UIViewController, UITableViewDataSource, UITableViewDelegate where BottomView: View, ReplyView: View {
    
    var delegate: MessageListControllerDelegate?
    
    let chatController: ChatController
    let userID: UserID
    let chatID: ChatID
    let action: MessageActionHandler
    
    var bottomControlView: () -> BottomView {
        didSet {
            hostedBottomControl?.rootView = bottomControlView()
        }
    }
    
    var canType: Bool {
        didSet {
            updateTableContentOffsetAndInsets()
            setInput(visible: canType)
        }
    }
    
    var showReply: Bool {
        didSet {
            setReplyVisible(visible: showReply)
        }
    }
    
    var replyView: () -> ReplyView {
        didSet {
            hostedReplyView?.rootView = replyView()
        }
    }
    
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let scrollButton = UIButton(type: .custom)
    
    private let defaultMemberName = "Member"
    
    private var isAroundBottom: Bool = false
    private var isLoadingMore: Bool = false
    
    private var state: ConversationState!
    
    private var messages: [MessageDescription]
    private var focus: Binding<FocusConfiguration?>?
    private var scroll: Binding<ScrollConfiguration?>?
    private var unreadBannerIndex: Int?
    
    private var stream: StreamMessagesReference?
    
    private var inputBar = MessageInputBar(frame: .zero)
    private var hostedBottomControl: UIHostingController<BottomView>?
    private var hostedReplyView: UIHostingController<ReplyView>?
    
    private var lastKnownInputHeight: CGFloat?
    private var lastKnownKeyboardHeight: CGFloat = 0
    
    private var replyShownConstraint: NSLayoutConstraint?
    private var replyHiddenConstraint: NSLayoutConstraint?
    
    private let replyViewHeight: CGFloat = 55
    private let bottomControlHeight: CGFloat = 55
    
    private let typingController = TypingController()
    private var typingPoller: Poller?
    
    private var isSwipingBack: Bool = false
    private var isTyping: Bool = false
    
    private var isTypingVisible: Bool {
        !typingUsers.isEmpty
    }
    
    private var typingUsers: [TypingProfile] = [] {
        didSet {
            typingController.setProfiles(typingUsers)
            if isTypingVisible {
                showTypingIndicator(visible: true)
            } else {
                showTypingIndicator(visible: false)
            }
        }
    }
    
    // MARK: - Init -
    
    init(
        chatController: ChatController,
        userID: UserID,
        chatID: ChatID,
        canType: Bool,
        @ViewBuilder bottomControlView: @escaping () -> BottomView,
        focus: Binding<FocusConfiguration?>?,
        scroll: Binding<ScrollConfiguration?>?,
        action: @escaping MessageActionHandler,
        showReply: Bool,
        @ViewBuilder replyView: @escaping () -> ReplyView
    ) {
        self.chatController = chatController
        self.userID         = userID
        self.chatID         = chatID
        self.canType        = canType
        self.bottomControlView = bottomControlView
        self.focus          = focus
        self.messages       = []
        self.showReply      = showReply
        self.replyView      = replyView
        self.scroll         = scroll
        self.action         = action
        
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
        DispatchQueue.main.async { [stream, chatController, chatID] in
            Task {
                try await chatController.sendTyping(state: .stopped, chatID: chatID)
            }
            
            trace(.warning, components: "Destroying conversation stream...")
            stream?.destroy()
        }
    }
    
    private func setupViews() {
        
        // Table View
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: .messageCell)
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: .typingCell)
        tableView.separatorStyle      = .none
        tableView.backgroundColor     = .clear
        tableView.allowsSelection     = false
        tableView.estimatedRowHeight  = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactiveWithAccessory
        tableView.delaysContentTouches = false
        view.addSubview(tableView)
        
        // Scroll Button
        
        scrollButton.translatesAutoresizingMaskIntoConstraints = false
        scrollButton.setImage(UIImage.asset(.scrollBottom), for: .normal)
        scrollButton.addTarget(self, action: #selector(animateToBottom), for: .touchUpInside)
        view.addSubview(scrollButton)
        
        // Reply view
        
        let hostedReplyView = UIHostingController(rootView: replyView())
        let replyView = hostedReplyView.view!
        replyView.translatesAutoresizingMaskIntoConstraints = false
        replyView.backgroundColor = .clear
        addChild(hostedReplyView)
        view.addSubview(replyView)
        hostedReplyView.didMove(toParent: self)
        self.hostedReplyView = hostedReplyView
        
        // Input hosting view
        
        inputBar.delegate = self
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)
        
        // Bottom control view
        
        let hostedBottomControl = UIHostingController(rootView: bottomControlView())
        let bottomControlView = hostedBottomControl.view!
        bottomControlView.translatesAutoresizingMaskIntoConstraints = false
        bottomControlView.backgroundColor = .backgroundMain
        addChild(hostedBottomControl)
        view.addSubview(bottomControlView)
        hostedBottomControl.didMove(toParent: self)
        self.hostedBottomControl = hostedBottomControl
        
        // Keyboard layout guide
        
        view.keyboardLayoutGuide.usesBottomSafeArea = false

        // Constraints
        
        replyShownConstraint = replyView.bottomAnchor.constraint(equalTo: inputBar.topAnchor)
        replyHiddenConstraint = replyView.topAnchor.constraint(equalTo: inputBar.topAnchor)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            replyView.heightAnchor.constraint(equalToConstant: replyViewHeight).setting(priority: .defaultHigh),
            replyView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 150),
            replyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            replyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyHiddenConstraint!,
            
            inputBar.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 150),
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            
            bottomControlView.heightAnchor.constraint(equalToConstant: bottomControlHeight),
            bottomControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomControlView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            scrollButton.bottomAnchor.constraint(lessThanOrEqualTo: replyView.topAnchor, constant: -20).setting(priority: .defaultHigh),
            scrollButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomControlView.topAnchor, constant: -20).setting(priority: .defaultHigh),
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(databaseDidChange(notification:)),              name: .databaseDidChange,                            object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillEnterForeground(notification:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground(notification:)),  name: UIApplication.didEnterBackgroundNotification,  object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameWillChange), name: UIWindow.keyboardWillChangeFrameNotification, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.interactivePopGestureRecognizer?.addTarget(self, action: #selector(handleSwipeBackGesture(_:)))
    }
    
    // MARK: - Swipe Back -
    
    @objc func handleSwipeBackGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isSwipingBack = true
        case .ended:
            isSwipingBack = false
        default:
            break
        }
    }
    
    // MARK: - Keyboard Handling -
    
    @objc
    private func keyboardFrameWillChange(_ notification: Notification) {
        guard let parameters = notification.extractKeyboardParameters(in: view) else {
            return
        }
        
        // 1. Step one is to find the intersection frame of the keyboard and
        // out scroll view to determine how much we need to scroll the content
        
        let contentFrame = CGRect(
            origin: .zero,
            size: tableView.contentSize
        )
        
        let intersectionFrame: CGRect
        
        // If the table view content is smaller than the bounds
        // (ie. it doesn't scroll), we'll need to find the size
        // of the content and intersect the keyboard frame with
        // this content frame instead of the bounds, otherwise
        // we'll end up scrolling up empty space from the bottom
        if contentFrame.height <= tableView.bounds.height {
            
            let inputHeight = computeKeyboardAccessoryHeight()
            
            var completeKeyboardFrame = parameters.endFrame
            completeKeyboardFrame.origin.y -= inputHeight
            completeKeyboardFrame.size.height += inputHeight
            
            let convertedContentFrame = view.convert(contentFrame, from: tableView)
            intersectionFrame = completeKeyboardFrame.intersection(convertedContentFrame)
        } else {
            intersectionFrame = parameters.endFrame.intersection(view.bounds)
        }
        
        // 2. Step two is to apply the height of the intersection as
        // an offset to the content to make the content move inline
        // with the keyboard as it slides up and changes size
        
        let keyboardHeight = intersectionFrame.size.height
        guard keyboardHeight > 0 else {
            return
        }
        
        let lastHeight = lastKnownKeyboardHeight
        
        let delta = keyboardHeight - lastHeight
        var offset = self.tableView.contentOffset
        offset.y += delta
        self.tableView.contentOffset = offset
        
        print("Moving up table content by: \(delta)")
        lastKnownKeyboardHeight += delta
    }
    
    // MARK: - Database Updates -
    
    @objc private func databaseDidChange(notification: Notification) {
        state.loadFromDatabase()
    }
    
    @objc private func applicationWillEnterForeground(notification: Notification) {
        startStream()
        if isTyping {
            setIsTyping(typing: true)
        }
    }
    
    @objc private func applicationDidEnterBackground(notification: Notification) {
        destroyStream()
        setIsTyping(typing: false)
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
            case .success(let update):
                switch update {
                case .messages(let messages):
                    self?.streamMessages(messages: messages)
                    
                case .typingUsers(let typingUsers):
                    self?.streamTypingUsers(users: typingUsers)
                }

            case .failure:
                self?.destroyStream()
            }
        }
    }
    
    private func streamMessages(messages: [Chat.Message]) {
        Task {
            try await chatController.receiveMessages(messages: messages, for: chatID)
            try await advanceReadPointer()
            
            if isAroundBottom {
                scrollTo(configuration: .init(destination: .bottom, animated: true))
            }
        }
    }
    
    private func streamTypingUsers(users: [TypingUser]) {
        Task {
            
            var usersStillTyping: Set<UUID> = []
            var usersToRemove: Set<UUID> = []
            
            for user in users {
                guard user.userID != self.userID else {
                    // Ignore self
                    continue
                }
                
                let id = user.userID.uuid
                
                switch user.typingState {
                case .unknown, .stopped, .timedOut:
                    usersToRemove.insert(id)
                    
                case .started, .stillTyping:
                    usersStillTyping.insert(id)
                }
            }
            
            var updatedUsers = typingUsers
            
            // Remove users that stopped typing
            updatedUsers = updatedUsers.filter { !usersToRemove.contains($0.serverID) }

            updatedUsers.forEach {
                usersStillTyping.insert($0.serverID)
            }
            
            if !usersStillTyping.isEmpty {
                let profiles = try chatController.getTypingProfiles(in: Array(usersStillTyping))
                typingUsers = profiles
            } else {
                typingUsers = []
            }
//            let count = profiles.count
//            typingUsers = profiles.enumerated().map { index, profile in
//                IndexedTypingUser(
//                    id: profile.serverID,
//                    index: count - index - 1,
//                    avatarURL: profile.socialProfile?.avatar?.bigger ?? profile.avatarURL
//                )
//            }
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
    
    func set(focus: Binding<FocusConfiguration?>?) {
        self.focus = focus
        
        consumeFocus()
    }
    
    private func consumeFocus() {
        guard let focus, let config = focus.wrappedValue else {
            return
        }
        
        if let focused = config.focused {
            if focused {
                _ = inputBar.becomeFirstResponder()
            } else {
                _ = inputBar.resignFirstResponder()
            }
        }
        
        if let clearInput = config.clearInput, clearInput {
            inputBar.clearText()
        }
        
        DispatchQueue.main.async {
            focus.wrappedValue = nil
        }
    }
    
    private func processRowsIntoDescriptions(rows: [MessageRow]?, unread: UnreadDescription?) {
        guard let rows else {
            return
        }
        
        let (messages, unreadIndex) = rows.messageDescriptions(userID: userID, unread: unread)
        
        self.messages = messages
        self.unreadBannerIndex = unreadIndex
        
        if isViewLoaded {
            reload()
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
            if case .message(let id, _, _, _, _, _) = $0.kind {
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
        guard !messages.isEmpty else {
            return
        }
        
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
        let threshold     = contentHeight - height - 100// - height / 2
        
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
            self.scrollButton.alpha = visible ? 1 : 0
        }
    }
    
    private func setInput(visible: Bool) {
        view.layoutIfNeeded()
        
        UIView.animate(withDuration: 0.15) {
            self.inputBar.alpha = visible ? 1 : 0
            self.hostedBottomControl?.view.alpha = visible ? 0 : 1
            self.view.layoutIfNeeded()
        }
    }
    
    private func showTypingIndicator(visible: Bool) {
        let indexPath = IndexPath(row: messages.count, section: 0)
        
        let rows = tableView.numberOfRows(inSection: 0)
        var didInsert: Bool = false
        
        tableView.beginUpdates()
        if visible {
            if rows == messages.count {
                didInsert = true
                tableView.insertRows(at: [indexPath], with: .fade)
            }
        } else {
            if rows > messages.count {
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        }
        tableView.endUpdates()
        
        if didInsert && isAroundBottom {
            tableView.scrollToRow(
                at: indexPath,
                at: .bottom,
                animated: true
            )
        }
    }
    
    private func setReplyVisible(visible: Bool) {
        view.layoutIfNeeded()

        self.replyHiddenConstraint?.isActive = !visible
        self.replyShownConstraint?.isActive = visible
        
        UIView.animate(withDuration: 0.25) {
            self.hostedReplyView?.view.alpha = visible ? 1 : 0
            
            self.updateTableContentOffsetAndInsets()
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - UITableViewDataSource -
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var count = messages.count
        
        if isTypingVisible {
            count += 1
        }
        
        return count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0..<messages.count: // Messages
            let cell = tableView.dequeueReusableCell(withIdentifier: .messageCell, for: indexPath) as! MessageTableCell
            return configureMessageCell(cell: cell, index: indexPath.row)
            
        case messages.count: // Typing indicator
            let cell = tableView.dequeueReusableCell(withIdentifier: .typingCell, for: indexPath) as! MessageTableCell
            return configureTypingCell(cell: cell)
            
        default:
            // Shouldn't ever hit this
            fatalError()
//            return cell
        }
    }
    
    private func configureMessageCell(cell: MessageTableCell, index: Int) -> MessageTableCell {
        let message = messages[index]
        let width = message.messageWidth(in: tableView.frame.size).width
        
        let reactions: [MessageReaction]
        if case .message(let messageID, _, _, _, _, _) = message.kind {
            reactions = try! chatController.getMessageReactions(messageID: messageID)
        } else {
            reactions = []
        }
        
        cell.backgroundColor = .clear
        cell.swipeEnabled    = message.kind.messageRow != nil && !message.kind.isDeleted
        cell.onSwipeToReply  = { [weak self] in
            self?.action(.reply(message.kind.messageRow!))
        }
        
        cell.onDoubleTap = { [weak self] in
            guard case .message(_, _, let row, _, let deletionState, _) = message.kind else { return }
            let isDeleted = deletionState != nil
            
            if !isDeleted, let senderID = row.message.senderID {
                self?.action(.tip(
                    UserID(uuid: senderID),
                    MessageID(uuid: row.message.serverID)
                ))
            }
        }
        
        cell.onLongPress = { [weak self, state, userID] in
            guard case .message(_, _, let row, _, let deletionState, _) = message.kind else { return }
            guard let state else { return }
            
            let hostID = UserID(uuid: state.room.room.ownerUserID)
            
            let message = row.message
            let member = row.member
            let isFromSelf = message.senderID == userID.uuid
            let displayName = row.member.resolvedDisplayName
            let isDeleted = deletionState != nil
            let selfIsHost = userID == hostID
            
            guard !isDeleted else {
                // No actions for deleted messages
                return
            }
            
            guard let senderID = member.userID else {
                return
            }
            
            let action = MessageActionDescription(
                messageID:         MessageID(uuid: message.serverID),
                senderID:          UserID(uuid: senderID),
                messageRow:        row,
                senderDisplayName: displayName,
                messageText:       message.content,
                showDeleteAction:  selfIsHost || isFromSelf,
                showSpeakerAction: selfIsHost && !isFromSelf,
                showMuteAction:    selfIsHost && !isFromSelf,
                showTipAction:     !isFromSelf,
                showReportAction:  !isFromSelf,
                showBlockAction:   !isFromSelf,
                isFromSelf:        isFromSelf,
                isMessageDeleted:  isDeleted,
                isSenderBlocked:   member.isBlocked == true,
                canSenderSend:     member.canSend == true
            )
            
            _ = self?.inputBar.resignFirstResponder()
            self?.delegate?.messageListControllerWillShowActionSheet(description: action)
        }
        
        cell.contentConfiguration = UIHostingConfiguration {
            let row = row(
                for: message,
                reactions: reactions,
                userID: userID,
                hostID: UserID(uuid: state.room.room.ownerUserID),
                action: action
            )
            
            MessageRowView(kind: message.kind, width: width) { row }
        }
        .minSize(width: 0, height: 20)
        .margins(.vertical, 2)
        .margins(.horizontal, 0)

        return cell
    }
    
    private func configureTypingCell(cell: MessageTableCell) -> MessageTableCell {
        cell.backgroundColor = .clear
        cell.swipeEnabled    = false
        
        cell.contentConfiguration = UIHostingConfiguration {
            TypingIndicatorView()
                .environment(typingController)
        }
        .minSize(width: 0, height: 20)
        .margins(.vertical, 2)
        .margins(.horizontal, 0)
        
        return cell
    }

    // MARK: - UITableViewDelegate -

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
    
    @ViewBuilder
    private func row(for description: MessageDescription, reactions: [MessageReaction], userID: UserID, hostID: UserID, action: @escaping MessageActionHandler) -> some View {
        switch description.kind {
        case .date(let date):
            MessageTitle(text: date.formattedRelatively())
            
        case .message(_, let isReceived, let row, let location, let deletionState, let referenceDeletion):
//            let message = row.message
//            let member = row.member
//            let isFromSelf = message.senderID == userID.uuid
//            let displayName = row.member.resolvedDisplayName
//            let isDeleted = deletionState != nil
//            let selfIsHost = userID == hostID
            
            MessageText(
                messageRow: row,
                reactions: reactions,
                text: description.content,
                isReceived: isReceived,
                hostID: hostID.uuid,
                deletionState: deletionState,
                replyingTo: replyingTo(for: row, deletion: referenceDeletion, action: action),
                location: location,
                action: { [weak self] messageAction in
                    self?.action(messageAction)
                }
            )
//            .onTapGesture(count: 2) {
//                if !isDeleted, let senderID = message.senderID {
//                    action(.tip(
//                        UserID(uuid: senderID),
//                        MessageID(uuid: message.serverID)
//                    ))
//                }
//            }
//            .gesture(LongPressGesture(minimumDuration: 0.35).onEnded { [weak self] _ in
//                guard !isDeleted else {
//                    // No actions for deleted messages
//                    return
//                }
//                
//                guard let senderID = member.userID else {
//                    return
//                }
//                
//                let action = MessageActionDescription(
//                    messageID:         MessageID(uuid: message.serverID),
//                    senderID:          UserID(uuid: senderID),
//                    messageRow:        row,
//                    senderDisplayName: displayName,
//                    messageText:       description.content,
//                    showDeleteAction:  selfIsHost || isFromSelf,
//                    showSpeakerAction: selfIsHost && !isFromSelf,
//                    showMuteAction:    selfIsHost && !isFromSelf,
//                    showTipAction:     !isFromSelf,
//                    showReportAction:  !isFromSelf,
//                    showBlockAction:   !isFromSelf,
//                    isFromSelf:        isFromSelf,
//                    isMessageDeleted:  isDeleted,
//                    isSenderBlocked:   member.isBlocked == true,
//                    canSenderSend:     member.canSend == true
//                )
//                
//                _ = self?.inputBar.resignFirstResponder()
//                self?.delegate?.messageListControllerWillShowActionSheet(description: action)
//            })
            
        case .announcement:
            MessageAnnouncement(text: description.content)
            
        case .announcementActionable:
            let selfIsHost = state.room.room.ownerUserID == userID.uuid
            let roomNumber = state.room.room.roomNumber
            MessageAnnouncementActionable(
                text: description.content,
                actionName: "Share a Link to \(selfIsHost ? "Your" : "This") Flipchat",
                action: {
                    ShareSheet.present(url: .flipchatRoom(roomNumber: roomNumber, messageID: nil))
                }
            )
            
        case .unread:
            MessageUnread(text: description.content)
        }
    }
    
    func replyingTo(for row: MessageRow, deletion: ReferenceDeletion?, action: @escaping MessageActionHandler) -> ReplyingTo? {
        guard
            let referenceID = row.referenceID,
            let reference = row.reference
        else {
            return nil
        }
        
        return .init(
            name: reference.resolvedDisplayName,
            verificationType: reference.profile?.verificationType ?? .none,
            content: reference.content,
            deletion: deletion,
            action: { [weak self] in
                self?.scrollTo(messageID: referenceID)
            }
        )
    }
}

// MARK: - MessageInputBarDelegate -

extension _MessagesListController: @preconcurrency MessageInputBarDelegate {
    func didResignFirstResponder() {
        // We need to know if the keyboard is being dismissed by
        // the system or if it's user-invoked dismissal. If it
        // wasn't the user, we'll leave the knownHeight intact
        // so that future keyboardDidChange notifications will
        // always subtract the last known height.
        if !isSwipingBack {
            
            lastKnownKeyboardHeight = 0
            print("Resetting last known height.")
            
            Task {
                delegate?.messageListControllerKeyboardDismissed()
            }
        }
    }
    
    func inputTextDidChange(text: String) {
        Task {
            if text.isEmpty {
                setIsTyping(typing: false)
            } else if !isTyping {
                setIsTyping(typing: true)
            }
        }
    }
    
    func setIsTyping(typing: Bool) {
        if typing {
            isTyping = true
            sendTypingUpdate(state: .started)
            
            typingPoller = Poller(seconds: 3) { [weak self] in
                self?.sendTypingUpdate(state: .stillTyping)
            }
            
        } else {
            isTyping = false
            typingPoller = nil
            sendTypingUpdate(state: .stopped)
        }
    }
    
    private func sendTypingUpdate(state: TypingState) {
        Task {
            try await chatController.sendTyping(state: state, chatID: chatID)
        }
    }
    
    func textContentHeightDidChange() {
        updateTableContentOffsetAndInsets()
    }
    
    func willSendMessage(text: String) -> Bool {
        let didSend = delegate?.messageListControllerWillSendMessage(text: text) ?? false
        
        setIsTyping(typing: false)
        
        return didSend
    }
    
    private func computeKeyboardAccessoryHeight() -> CGFloat {
        var height: CGFloat = 0
        
        if canType {
            height += inputBar.frame.height + 18
        } else {
            height += bottomControlHeight + 15
        }
        
        if showReply {
            height += replyViewHeight
        }
        
//        if !typingUsers.isEmpty {
//            height += typingViewHeight
//        }
        
        return height
    }
    
    private func updateTableContentOffsetAndInsets() {
        let height = computeKeyboardAccessoryHeight()
        
        // 1. Update tableview content offset first
        if let lastKnownInputHeight {
            let delta = height - lastKnownInputHeight
            if delta != 0 {
                tableView.contentOffset.y += delta
                print("Last known: \(lastKnownInputHeight), new height: \(height), delta: \(delta)")
            }
        }
        
        // 2. Update keyboard dismiss padding
        view.keyboardLayoutGuide.keyboardDismissPadding = height
        
        // 3. Update content insets and scroll insets
        var insets: UIEdgeInsets = .init(
            top: 0, // 10
            left: 0,
            bottom: 0, // 15
            right: 0
        )
        
        insets.bottom += height
        
        // Setting the content inset AFTER
        // updating the contentOffset results
        // in smoother and more predictable
        // placement. Otherwise, we get a shift
        
        tableView.contentInset = insets
        tableView.scrollIndicatorInsets = insets
        
        lastKnownInputHeight = height
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
        case .message(_, let isReceived, _, _, _, _):
            return isReceived ? .leading : .trailing
        case .announcement, .unread, .announcementActionable:
            return .center
        }
    }
    
    private var alignment: Alignment {
        switch kind {
        case .date:
            return .top
        case .message(_, let isReceived, _, _, _, _):
            return isReceived ? .leading : .trailing
        case .announcement, .unread, .announcementActionable:
            return .bottom
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch kind {
        case .date, .message, .announcement, .announcementActionable:
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
                case .date, .announcement, .unread, .announcementActionable:
                    content()
                    
                case .message(_, let isReceived, _, _, _, _):
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

struct FocusConfiguration {
    var focused: Bool?
    var clearInput: Bool?
    
    init(focused: Bool? = nil, clearInput: Bool? = nil) {
        self.focused = focused
        self.clearInput = clearInput
    }
}

struct UnreadDescription {
    var messageID: UUID
    var unread: Int
}

private extension String {
    static let messageCell = "messageCell"
    static let typingCell  = "typingCell"
}
