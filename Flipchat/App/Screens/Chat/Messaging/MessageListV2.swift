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
            setVisible(isTyping: isTypingVisible, isReplying: showReply)
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
    private var hostedTypingView: UIHostingController<TypingIndicatorView>?
    
    private var lastKnownInputHeight: CGFloat?
    private var lastKnownKeyboardHeight: CGFloat = 0
    
    private var replyShownConstraint: NSLayoutConstraint?
    private var replyHiddenConstraint: NSLayoutConstraint?
    
    private var typingShownOnInputConstraint: NSLayoutConstraint?
    private var typingShownOnReplyConstraint: NSLayoutConstraint?
    private var typingHiddenConstraint: NSLayoutConstraint?
    
    private let typingViewHeight: CGFloat = 50
    private let replyViewHeight: CGFloat = 55
    private let descriptionViewHeight: CGFloat = 52
    
    private var typingPoller: Poller?
    
    private var isTyping: Bool = false
    
    private var isTypingVisible: Bool {
        !typingUsers.isEmpty
    }
    
    private var typingUsers: [IndexedTypingUser] = [] {
        didSet {
            hostedTypingView?.rootView = TypingIndicatorView(typingUsers: typingUsers)
            setVisible(isTyping: isTypingVisible, isReplying: showReply)
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
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: "cell")
        tableView.separatorStyle      = .none
        tableView.backgroundColor     = .clear
        tableView.allowsSelection     = false
        tableView.estimatedRowHeight  = UITableView.automaticDimension
        tableView.keyboardDismissMode = .interactiveWithAccessory
        view.addSubview(tableView)
        
        // Scroll Button
        
        scrollButton.translatesAutoresizingMaskIntoConstraints = false
        scrollButton.setImage(UIImage.asset(.scrollBottom), for: .normal)
        scrollButton.addTarget(self, action: #selector(animateToBottom), for: .touchUpInside)
        
        // Typing view
        
        let hostedTypingView = UIHostingController(rootView: TypingIndicatorView(typingUsers: []))
        let typingView = hostedTypingView.view!
        typingView.translatesAutoresizingMaskIntoConstraints = false
        typingView.backgroundColor = .clear
        addChild(hostedTypingView)
        view.addSubview(typingView)
        hostedTypingView.didMove(toParent: self)
        self.hostedTypingView = hostedTypingView
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
        
        typingShownOnInputConstraint = typingView.bottomAnchor.constraint(equalTo: inputBar.topAnchor)
        typingShownOnReplyConstraint = typingView.bottomAnchor.constraint(equalTo: replyView.topAnchor)
        typingHiddenConstraint = typingView.topAnchor.constraint(equalTo: inputBar.topAnchor)
        
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
            
            typingView.heightAnchor.constraint(equalToConstant: typingViewHeight).setting(priority: .defaultHigh),
            typingView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 150),
            typingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            typingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            typingHiddenConstraint!,
            
            inputBar.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 150),
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            
            bottomControlView.heightAnchor.constraint(equalToConstant: descriptionViewHeight),
            bottomControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomControlView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            scrollButton.bottomAnchor.constraint(lessThanOrEqualTo: typingView.topAnchor, constant: -20).setting(priority: .defaultHigh),
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
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),        name: UIWindow.keyboardWillHideNotification,        object: nil)
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
    
    @objc
    private func keyboardWillHide(_ notification: Notification) {
        print("Resetting last known height.")
        lastKnownKeyboardHeight = 0
        
        Task {
            delegate?.messageListControllerKeyboardDismissed()
        }
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
            updatedUsers = updatedUsers.filter { !usersToRemove.contains($0.id) }

            updatedUsers.forEach {
                usersStillTyping.insert($0.id)
            }
            
            let profiles = try chatController.getTypingProfiles(in: Array(usersStillTyping))
            let count = profiles.count
            typingUsers = profiles.enumerated().map { index, profile in
                IndexedTypingUser(
                    id: profile.serverID,
                    index: count - index - 1,
                    avatarURL: profile.socialAvatar?.bigger ?? profile.avatarURL
                )
            }
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
        
        if config.focused {
            _ = inputBar.becomeFirstResponder()
        } else {
            _ = inputBar.resignFirstResponder()
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
        
        // Determine if we should scroll to the bottom
//        let lastNewMessageID = messages.last?.kind.messageRow?.message.serverID
//        let lastCurrentMessageID = self.messages.last?.kind.messageRow?.message.serverID
//        var shouldScroll = false
//        if
//            let lastNewMessageID,
//            let lastCurrentMessageID,
//            lastNewMessageID > lastCurrentMessageID, // Only scroll if there's newer messages
//            isAroundBottom, // Only scroll if we're close to the bottom
//            !self.messages.isEmpty // Only scroll if we're updating not initializing the list
//        {
//            shouldScroll = true
//        }
        
        self.messages = messages
        self.unreadBannerIndex = unreadIndex
        
        if isViewLoaded {
            reload()
            
            // Scroll after the table view has reloaded
//            if shouldScroll {
//                animateToBottom()
//            }
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
    
    private func setVisible(isTyping: Bool, isReplying: Bool) {
        view.layoutIfNeeded()
        
        self.typingHiddenConstraint?.isActive = !isTyping
        if showReply {
            self.typingShownOnReplyConstraint?.isActive = isTyping
            self.typingShownOnInputConstraint?.isActive = false
        } else {
            self.typingShownOnReplyConstraint?.isActive = false
            self.typingShownOnInputConstraint?.isActive = isTyping
        }
        
        // Has to come after we update the typing view
        // constraints, otherwise it'll hang
        self.replyHiddenConstraint?.isActive = !isReplying
        self.replyShownConstraint?.isActive = isReplying
        
        UIView.animate(withDuration: 0.25) {
            let state: CGFloat = isTyping ? 1 : 0
            
            // Typing
            self.hostedTypingView?.view.alpha = state
            
            // Reply
            self.hostedReplyView?.view.alpha = isReplying ? 1 : 0
            
            self.updateTableContentOffsetAndInsets()
            self.view.layoutIfNeeded()
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
        cell.swipeEnabled    = message.kind.messageRow != nil && !message.kind.isDeleted
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
            
        case .message(_, let isReceived, let row, let location, let deletionState, let referenceDeletion):
            let message = row.message
            let member = row.member
            let isFromSelf = message.senderID == userID.uuid
            let displayName = row.member.resolvedDisplayName
            let chatID = chatID
            let isDeleted = deletionState != nil
            let selfIsHost = userID == hostID
            
            MessageText(
                messageRow: row,
                text: description.content,
                isReceived: isReceived,
                hostID: hostID.uuid,
                deletionState: deletionState,
                replyingTo: replyingTo(for: row, deletion: referenceDeletion, action: action),
                location: location,
                action: { [weak self] messageAction in
                    self?.action(messageAction)
                }
            ) {
                // Don't show action for deleted messages
                if !isDeleted {
                    
                    if selfIsHost, !isFromSelf, let userID = member.userID {
                        
                        if member.canSend == true {
                            Button {
                                action(.demoteUser(member.resolvedDisplayName, UserID(uuid: userID), chatID))
                            } label: {
                                Label("Remove as Speaker", systemImage: "speaker.slash")
                            }
                        } else {
                            Button {
                                action(.promoteUser(member.resolvedDisplayName, UserID(uuid: userID), chatID))
                            } label: {
                                Label("Make a Speaker", systemImage: "speaker.wave.2.bubble")
                            }
                        }
                        
                        Divider()
                    }
                    
                    // Regular actions
                    
                    Button {
                        Task {
                            action(.reply(row))
                        }
                    } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.backward.fill")
                    }
                    
                    if let senderID = message.senderID, senderID != userID.uuid {
                        Button {
                            Task {
                                action(.tip(
                                    UserID(uuid: senderID),
                                    MessageID(uuid: message.serverID)
                                ))
                            }
                        } label: {
                            Label("Give Tip", systemImage: "dollarsign")
                        }
                    }
                    
                    
                    Button {
                        action(.copy(description.content))
                    } label: {
                        Label("Copy Message", systemImage: "doc.on.doc")
                    }
                    
                    // Destructive actions
                    Divider()
                    
                    // Allow deletes for self messages or if room host is deleting a message
                    if let senderID = message.senderID, senderID == userID.uuid || userID == hostID {
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
            }
            .onTapGesture(count: 2) {
                if !isDeleted, let senderID = message.senderID {
                    action(.tip(
                        UserID(uuid: senderID),
                        MessageID(uuid: message.serverID)
                    ))
                }
            }
            
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
            name: reference.displayName ?? defaultMemberName,
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
        delegate?.messageListControllerWillSendMessage(text: text) ?? false
    }
    
    private func computeKeyboardAccessoryHeight() -> CGFloat {
        var height: CGFloat = 0
        
        if canType {
            height += inputBar.frame.height + 18
        } else {
            height += descriptionViewHeight + 18
        }
        
        if showReply {
            height += replyViewHeight
        }
        
        if !typingUsers.isEmpty {
            height += typingViewHeight
        }
        
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
    var focused: Bool
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
            case .text, .announcement, .reply, .announcementActionable:
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
                let referenceID = messageContainer.row.referenceID
                let isReceived = message.senderID != userID.uuid
                
                var deletionState: MessageDeletion?
                var referenceDeletionState: ReferenceDeletion?
                
                if let deletionUser = deletedIDs[message.serverID] {
                    deletionState = MessageDeletion(
                        senderID: deletionUser?.uuid,
                        senderName: messageContainer.row.member.resolvedDisplayName,
                        isSelf: deletionUser == userID,
                        isSender: deletionUser?.uuid == message.senderID
                    )
                }
                
                if let referenceID, let deletionUser = deletedIDs[referenceID] {
                    referenceDeletionState = ReferenceDeletion(
                        senderID: deletionUser?.uuid,
                        senderName: messageContainer.row.member.resolvedDisplayName,
                        isSelf: deletionUser == userID,
                        isSender: deletionUser?.uuid == message.senderID
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
                                deletionState,
                                referenceDeletionState
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
                    
                case .announcementActionable:
                    container.append(
                        .init(
                            kind: .announcementActionable(ID(uuid: message.serverID)),
                            content: message.content
                        )
                    )
                    
                case .reaction, .tip, .deleteMessage, .unknown:
                    break
                }
            }
        }
        
        // 4. If unread description is present, we'll augment the list of
        // messages to include an unread banner as a 'message' row. The
        // pointer is to the last seen message so we have to insert the
        // banner after the message itself.
        if let unread, unread.unread > 0 {
            if let index = container.findLastReadMessageIndex(lastReadMessage: unread.messageID), index < container.count {
                let description = MessageDescription(
                    kind: .unread,
                    content: "\(unread.unread) Unread Message\(unread.unread == 1 ? "" : "s")"
                )
                
                container.insert(description, at: index)
                unreadIndex = index
            }
        }
        
        return (container, unreadIndex)
    }
}

extension Array where Element == MessageDescription {
    func findLastReadMessageIndex(lastReadMessage: UUID) -> Int? {
        for (index, message) in reversed().enumerated() {
            guard let messageID = message.serverID else {
                continue
            }
            
            if lastReadMessage >= messageID, index != 0 {
                // Add 1 at the end to insert the banner
                // after this message, not before it
                return count - 1 - index + 1
            }
        }
        
        return nil
    }
}

extension NSLayoutConstraint {
    func setting(priority: UILayoutPriority) -> Self {
        self.priority = priority
        return self
    }
}
