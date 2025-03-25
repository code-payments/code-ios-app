//
//  ConversationScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-30.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct ConversationScreen: View {
    
    @EnvironmentObject private var banners: Banners
    @EnvironmentObject private var notificationController: NotificationController
    
    @ObservedObject private var containerViewModel: ContainerViewModel
    @ObservedObject private var chatViewModel: ChatViewModel
    @ObservedObject private var session: Session
    
    @State private var focusConfiguration: FocusConfiguration?
    
    @State private var scrollConfiguration: ScrollConfiguration?
    
    @State private var replyMessage: MessageRow?
    
    @State private var shouldScrollOnFocus: Bool = true
    
    @State private var isShowingOpenClose: Bool = false
    
    @State private var isShowingInputForPaidMessage: Bool = false
    
    @State private var listenerMessage: ListenerMessage?
    
    @State private var tipUsers: TipUsers?
    
    @State private var messageTip: MessageTip?
    
    @State private var userProfileID: UserID?
    
    @State private var actionSheetMessageDescription: MessageActionDescription?
    
    private let chatID: ChatID
    private let state: AuthenticatedState
    private let container: AppContainer
    private let userID: UserID
    private let chatController: ChatController
    
    @StateObject private var updateableRoom: Updateable<RoomDescription?>
    @StateObject private var updateableUser: Updateable<MemberRow?>
    
    private var roomDescription: RoomDescription? {
        updateableRoom.value
    }
    
    private var selfUser: MemberRow? {
        updateableUser.value
    }
    
    private var canSend: Bool {
        selfUser?.canSend == true
    }
    
    private var isUserMuted: Bool {
        selfUser?.isMuted == true
    }
    
    private var roomHostID: UUID? {
        roomDescription?.room.ownerUserID
    }
    
    private var isSelfHost: Bool {
        roomHostID == userID.uuid
    }
    
    private var isRoomOpen: Bool {
        roomDescription?.room.isOpen == true
    }
    
    private var messageCost: Kin {
        roomDescription?.room.cover ?? 0
    }
    
    private var canShowOpenClose: Bool {
        isSelfHost && !isRoomOpen
    }
    
    private var isInputVisible: Bool {
        (chatController.isRegistered && canSend) || isShowingInputForPaidMessage
    }
    
    private var canType: Bool {
        !isUserMuted && isRoomOpen && isInputVisible
    }
    
    // MARK: - Init -
    
    init(chatID: ChatID, state: AuthenticatedState, container: AppContainer) {
        self.chatID = chatID
        self.state = state
        self.container = container
        self.session = state.session
        self.containerViewModel = state.containerViewModel
        self.chatViewModel = state.chatViewModel
        
        let userID = state.session.userID
        let chatController = state.chatController
        
        self.userID = userID
        self.chatController = chatController
        
        self._updateableRoom = .init(wrappedValue: Updateable {
            try? chatController.getRoom(chatID: chatID)
        })
        
        self._updateableUser = .init(wrappedValue: Updateable {
            try? chatController.getMember(userID: userID, roomID: chatID)
        })
    }
    
    private func didAppear() {
        setOpenClose(visible: true, animated: false)
    }
    
    private func didDisappear() {
        
    }
    
    // MARK: - Actions -
    
    private func setOpenClose(visible: Bool, animated: Bool) {
        func action() {
            isShowingOpenClose = canShowOpenClose && visible
        }
        
        if animated {
            withAnimation(.easeInOut(duration: 0.15)) {
                action()
            }
        } else {
            action()
        }
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                ScrollBox(color: .backgroundMain, ignoreEdges: [.bottom], edgePadding: 12) {
                    MessagesListController(
                        delegate: self,
                        chatController: chatController,
                        userID: userID,
                        chatID: chatID,
                        canType: canType,
                        bottomControlView: descriptionView,
                        focus: $focusConfiguration,
                        scroll: $scrollConfiguration,
                        action: { action in
                            Task {
                                try await messageAction(action: action)
                            }
                        },
                        showReply: replyMessage != nil && isInputVisible,
                        replyView: replyView
                    )
                    .ignoresSafeArea(.keyboard)
                }
                .sheet(isPresented: $chatViewModel.isShowingCreateAccountFromConversation) {
                    CreateAccountScreen(
                        storeController: state.storeController,
                        viewModel: OnboardingViewModel(
                            state: state,
                            container: container,
                            isPresenting: $chatViewModel.isShowingCreateAccountFromConversation
                        ) {
                            messageAsListenerAction()
                        }
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isShowingInputForPaidMessage)
        }
        .onAppear(perform: didAppear)
        .onDisappear(perform: didDisappear)
        .interactiveDismissDisabled()
        .navigationBarHidden(false)
        .navigationBarTitle("", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                titleItem()
            }
            
            // Spacer is require to prevent the titleItem
            // from colliding with the the moreItem. The
            // system doesn't truncate .topBarLeading
            ToolbarItem(placement: .principal) {
                Spacer()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                moreItem()
            }
        }
        .sheet(item: $messageTip) { tip in
            PartialSheet {
                ModalTipConfirmation(
                    balance: session.currentBalance,
                    primaryAction: "Swipe to Tip",
                    secondaryAction: "Cancel",
                    paymentAction: { kin in
                        try await chatController.sendTip(
                            amount: kin,
                            chatID: chatID,
                            messageID: tip.messageID,
                            messageUserID: tip.userID
                        )
                    },
                    dismissAction: {
                        messageTip = nil
                    },
                    cancelAction: {
                        messageTip = nil
                    }
                )
            }
        }
        .sheet(item: $tipUsers) { tipUsers in
            ModalTipList(
                userTips: tipUsers.users.map {
                    ModalTipList.UserTip(
                        userID: $0.userID,
                        avatarURL: $0.profile?.avatar?.bigger,
                        name: $0.resolvedDisplayName,
                        verificationType: $0.profile?.verificationType ?? .none,
                        isHost: $0.userID == roomHostID,
                        amount: $0.tip
                    )
                }
            )
        }
        .sheet(item: $listenerMessage) { listenerMessage in
            PartialSheet(canDismiss: false) {
                ModalPaymentConfirmation(
                    amount: messageCost.formattedFiat(rate: .oneToOne, truncated: true, showOfKin: true),
                    currency: .kin,
                    primaryAction: "Swipe to Pay",
                    secondaryAction: "Cancel",
                    paymentAction: {
                        solicitMessage(text: listenerMessage.text)
                    },
                    dismissAction: { dismissMessagePayment(cancelled: false) },
                    cancelAction:  { dismissMessagePayment(cancelled: true) }
                )
            }
        }
        .sheet(item: $userProfileID) { userID in
            ProfileScreen(
                userID: userID,
                isSelf: self.userID == userID,
                state: state,
                container: container
            )
        }
        .buttonSheet(item: $actionSheetMessageDescription) { description in
            if description.showSpeakerAction {
                if description.canSenderSend {
                    Action.standard(
                        systemImage: "speaker.slash",
                        title: "Remove as Speaker",
                        action: { try await speakerAction(canSend: description.canSenderSend, description) }
                    )
                } else {
                    Action.standard(
                        systemImage: "speaker.wave.2.bubble",
                        title: "Make a Speaker",
                        action: { try await speakerAction(canSend: description.canSenderSend, description) }
                    )
                }
            }
            
            Action.standard(
                systemImage: "arrowshape.turn.up.backward.fill",
                title: "Reply",
                action: { replyAction(description.messageRow) }
            )
            
            if description.showTipAction {
                Action.standard(
                    systemImage: "dollarsign",
                    title: "Give Tip",
                    action: { tipAction(description) }
                )
            }
            
            Action.standard(
                systemImage: "doc.on.doc",
                title: "Copy Message",
                action: { copyAction(description) }
            )
            
            // ------- Destructive Actions
            
            if description.showDeleteAction {
                Action.destructive(
                    systemImage: "trash",
                    title: "Delete",
                    action: { try await deleteAction(description) }
                )
            }
            
            if description.showReportAction {
                Action.destructive(
                    systemImage: "exclamationmark.shield",
                    title: "Report",
                    action: { try await reportAction(description) }
                )
            }
            
            if description.showMuteAction {
                Action.destructive(
                    systemImage: "speaker.slash",
                    title: "Mute",
                    action: { try await muteAction(description) }
                )
            }
            
            if description.showBlockAction {
                if description.isSenderBlocked {
                    Action.destructive(
                        systemImage: "person.slash",
                        title: "Unblock",
                        action: { try await blockAction(blocked: description.isSenderBlocked, description) }
                    )
                } else {
                    Action.destructive(
                        systemImage: "person.slash",
                        title: "Block",
                        action: { try await blockAction(blocked: description.isSenderBlocked, description) }
                    )
                }
            }
        }
//        .sheet(item: $actionSheetMessageID) { tip in
//            EmojiGrid { emoji in
//                print("Did select emoji")
//                actionSheetMessageID = nil
//            }
//        }
    }
    
    @ViewBuilder private func descriptionView() -> some View {
        VStack {
            if isUserMuted {
                mutedView()
                
            } else if !isRoomOpen {
                if isSelfHost {
                    openCloseView(isOpen: false)
                } else {
                    roomClosedView()
                }
                
            } else if !isInputVisible {
                CodeButton(
                    style: .filledMedium,
                    title: "Listener Message: \(messageCost.formattedTruncatedKin())",
                    action: messageAsListenerAction
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: canType)
    }
    
    @ViewBuilder private func replyView() -> some View {
        VStack(alignment: .leading) {
            if let replyMessage {
                MessageReplyBanner(
                    name: replyMessage.member.resolvedDisplayName,
                    verificationType: replyMessage.member.profile?.verificationType ?? .none,
                    content: replyMessage.message.content
                ) {
                    self.replyMessage = nil
                }.transition(.move(edge: .bottom))
            }
            
//            if isShowingOpenClose {
//                openCloseView(isOpen: isRoomOpen)
//                    .transition(.move(edge: .bottom))
//            }
        }
        .animation(.easeInOut(duration: 0.2), value: replyMessage)
    }
    
    @ViewBuilder private func mutedView() -> some View {
        VStack {
            Text("You've been muted")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
    }
    
    @ViewBuilder private func roomClosedView() -> some View {
        VStack {
            Text("The host has temporarily closed this Flipchat. Only they can send messages until they reopen it")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }
    
    @ViewBuilder private func openCloseView(isOpen: Bool) -> some View {
        HStack {
            Text("Your Flipchat is currently \(isOpen ? "open" : "closed")")
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            PillButton(text: isOpen ? "Change" : "Reopen") {
                
                let title: String
                let description: String
                let actionTitle: String
                let action: () -> Void
                
                if isOpen {
                    title = "Close Flipchat Temporarily?"
                    description = "Only you will be able to send messages until you reopen your Flipchat."
                    actionTitle = "Close Temporarily"
                    action = {
                        chatViewModel.setRoomStatus(chatID: chatID, open: false)
                    }
                } else {
                    title = "Reopen Flipchat?"
                    description = "People will be able to send messages again"
                    actionTitle = "Reopen Flipchat"
                    action = {
                        chatViewModel.setRoomStatus(chatID: chatID, open: true)
                        setOpenClose(visible: false, animated: true)
                    }
                }
                
                banners.show(
                    style: .notification,
                    title: title,
                    description: description,
                    position: .bottom,
                    actions: [
                        .standard(title: actionTitle, action: action),
                        .cancel(title: "Cancel"),
                    ]
                )
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder private func titleItem() -> some View {
        Button {
            showChatDetails()
        } label: {
            HStack(spacing: 10) {
                RoomGeneratedAvatar(data: chatID.data, diameter: 30)
                
                if let roomDescription = updateableRoom.value {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(roomDescription.room.formattedTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.appTextMedium)
                            .foregroundColor(.textMain)
                        
                        Text(String.formattedListenerCount(count: roomDescription.memberCount))
                            .lineLimit(1)
                            .font(.appTextHeading)
                            .foregroundColor(.textSecondary)
                    }
                }
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder private func moreItem() -> some View {
        Button {
            showChatDetails()
        } label: {
            Image.asset(.more)
                .padding(.vertical, 10)
                .padding(.leading, 20)
                .padding(.trailing, 20)
        }
        .padding(.trailing, -10)
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions -
    
    private func dismissKeyboardFocus() {
        focusConfiguration = .init(focused: false)
    }
    
    private func showChatDetails() {
        dismissKeyboardFocus()
        containerViewModel.pushDetails(chatID: chatID)
    }
    
    private func dismissMessagePayment(cancelled: Bool) {
        listenerMessage = nil
        
        // The "pay to message" button move the table view up
        // so we need to scroll to bottom to realign the edge
        scrollConfiguration = .init(destination: .bottom, animated: true)
        
        if cancelled {
            isShowingInputForPaidMessage = true
            focusConfiguration = .init(focused: true)
        }
    }
    
    private func speakerAction(canSend: Bool, _ description: MessageActionDescription) async throws {
        dismissKeyboardFocus()
        
        // Gives the context menu time to animate
        try await Task.delay(milliseconds: 200)
        
        let title: String
        let desc: String
        let action: String
        
        if description.canSenderSend {
            title  = "Remove \(description.senderDisplayName) as a Speaker?"
            desc   = "They will no longer be able to message for free"
            action = "Remove as Speaker"
        } else {
            title  = "Make \(description.senderDisplayName) a Speaker?"
            desc   = "They will be able to message for free"
            action = "Make a Speaker"
        }
        
        banners.show(
            style: .notification,
            title: title,
            description: desc,
            position: .bottom,
            actions: [
                .standard(title: action) {
                    Task {
                        if description.canSenderSend {
                            try await chatController.demoteUser(userID: description.senderID, chatID: chatID)
                        } else {
                            try await chatController.promoteUser(userID: description.senderID, chatID: chatID)
                        }
                    }
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    private func copyAction(_ description: MessageActionDescription) {
        copy(text: description.messageText)
    }
    
    private func replyAction(_ row: MessageRow) {
        if !isInputVisible {
            messageAsListenerAction()
        }
        
        replyMessage = row
        shouldScrollOnFocus = false
        focusConfiguration = .init(focused: true)
    }
    
    private func tipAction(_ description: MessageActionDescription) {
        if !description.isFromSelf {
            messageTip = .init(userID: description.senderID, messageID: description.messageID)
        }
    }
    
    private func deleteAction(_ description: MessageActionDescription) async throws {
        // Gives the context menu time to animate
        try await Task.delay(milliseconds: 200)
        
        banners.show(
            style: .error,
            title: "Delete Message?",
            description: "This message will be deleted for everyone.",
            position: .bottom,
            actions: [
                .destructive(title: "Delete") {
                    Task {
                        try await chatController.deleteMessage(messageID: description.messageID, for: chatID)
                    }
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    private func reportAction(_ description: MessageActionDescription) async throws {
        // Gives the context menu time to animate
        try await Task.delay(milliseconds: 200)
        
        banners.show(
            style: .error,
            title: "Report Message?",
            description: "This message will be forwarded to Flipchat. This contact will not be notified",
            position: .bottom,
            actions: [
                .destructive(title: "Report") {
                    Task {
                        try await chatController.reportMessage(userID: description.senderID, messageID: description.messageID)
                        showReportSuccess()
                    }
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    private func muteAction(_ description: MessageActionDescription) async throws {
        // Gives the context menu time to animate
        try await Task.delay(milliseconds: 200)
        
        banners.show(
            style: .error,
            title: "Mute \(description.senderDisplayName)?",
            description: "They will remain in the chat but will not be able to send messages",
            position: .bottom,
            actions: [
                .destructive(title: "Mute") {
                    Task {
                        try await chatController.muteUser(userID: userID, chatID: chatID)
                    }
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    private func blockAction(blocked: Bool, _ description: MessageActionDescription) async throws {
        // Gives the context menu time to animate
        try await Task.delay(milliseconds: 200)
        
        let title: String
        let desc: String
        
        if description.isSenderBlocked {
            title = "Unblock \(description.senderDisplayName)?"
            desc  = "All messages from this user will be visible again"
        } else {
            title = "Block \(description.senderDisplayName)?"
            desc  = "All messages from this user will be hidden"
        }
        
        banners.show(
            style: .error,
            title: title,
            description: desc,
            position: .bottom,
            actions: [
                .destructive(title: title) {
                    Task {
                        try await chatController.setUserBlocked(userID: description.senderID, blocked: !description.isSenderBlocked)
                    }
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
    
    private func messageAction(action: MessageAction) async throws {
        switch action {
        case .reply(let messageRow):
            replyAction(messageRow)
            
        case .linkTo(let roomNumber):
            chatViewModel.previewChat(
                roomNumber: roomNumber,
                showSuccess: false,
                showModally: true
            )
            
        case .tip(let userID, let messageID):
            // Can't tip yourself
            if self.userID != userID {
                messageTip = .init(userID: userID, messageID: messageID)
            }
            
        case .showTippers(let messageID):
            guard let users = try? chatController.getTipUsers(messageID: messageID) else {
                return
            }
            
            tipUsers = .init(
                messageID: messageID,
                users: users
            )
            
        case .openProfile(let userID):
            dismissKeyboardFocus()
            userProfileID = userID
        }
    }
    
    private func copy(text: String) {
        UIPasteboard.general.string = text
    }
    
//    private func changeRoomOpenState(open: Bool) {
//        Task {
//            try await chatController.changeRoomOpenState(chatID: chatID, open: open)
//        }
//    }
    
    private func sendMessageAction(text: String) -> Bool {
        if isShowingInputForPaidMessage {
            listenerMessage = .init(text: text)
            dismissKeyboardFocus()
            return false
        } else {
            sendMessage(text: text)
            return true
        }
    }
    
    private func messageAsListenerAction() {
        chatViewModel.attemptPayForMessage {
            isShowingInputForPaidMessage = true
            
            // This completion only runs when there's
            // no other dependencies for send message
            Task {
                try await Task.delay(milliseconds: 200)
                focusConfiguration = .init(focused: true)
            }
        }
    }
    
    private func solicitMessage(text: String) {
        guard let roomHostID else {
            return
        }
        
        Task {
            try await chatController.solicitMessage(
                text: text,
                chatID: chatID,
                hostID: UserID(uuid: roomHostID),
                amount: messageCost,
                replyingTo: MessageID(uuid: replyMessage?.message.serverID)
            )
            
            resetReply()
            focusConfiguration = .init(clearInput: true)
            
            try await Task.delay(milliseconds: 150)
            
            scrollToBottom(animated: true)
        }
    }
    
    private func sendMessage(text: String) {
        guard !text.isEmpty else {
            return
        }
        
        Task {
            try await chatController.sendMessage(
                text: text,
                for: chatID,
                replyingTo: MessageID(uuid: replyMessage?.message.serverID)
            )
            
            resetReply()
            
            try await Task.delay(milliseconds: 150)
            
            scrollToBottom(animated: true)
        }
    }
    
    private func resetReply() {
        replyMessage = nil
    }
    
    private func scrollToBottom(animated: Bool = false) {
        scrollConfiguration = .init(destination: .bottom, animated: animated)
    }
    
    // MARK: - Banners -
    
    private func showError(error: Error) {
        banners.show(
            style: .error,
            title: "Stream Failed",
            description: "Failed to establish a messages stream: \(error.localizedDescription)",
            position: .top,
            actions: [
                .cancel(title: Localized.Action.ok),
            ]
        )
    }
    
    private func showReportSuccess() {
        banners.show(
            style: .notification,
            title: "Report Sent",
            description: "Your report was sent successfully.",
            position: .top,
            actions: [
                .cancel(title: Localized.Action.ok),
            ]
        )
    }
}

extension ConversationScreen: @preconcurrency MessageListControllerDelegate {
    func messageListControllerKeyboardDismissed() {
        if isShowingInputForPaidMessage {
            isShowingInputForPaidMessage = false
        }
    }
    
    func messageListControllerWillSendMessage(text: String) -> Bool {
        sendMessageAction(text: text)
    }
    
    func messageListControllerWillShowActionSheet(description: MessageActionDescription) {
        actionSheetMessageDescription = description
        Feedback.buttonTap()
    }
}

struct ListenerMessage: Identifiable {
    public var id: String { text }
    
    var text: String
}

struct MessageTip: Identifiable {
    public var id: Data {
        messageID.data
    }
    
    let userID: UserID
    let messageID: MessageID
}

struct TipUsers: Identifiable {
    public var id: Data {
        messageID.data
    }
    
    let messageID: MessageID
    let users: [TipUser]
}

extension ID: @retroactive Identifiable {
    public var id: Data {
        data
    }
}

//#Preview {
//    let userID1 = ID.random
//    let userID2 = ID.random
//    let chatID  = ID.random
//    let hostID  = userID1
// 
//    Background(color: .backgroundMain) {
//        MessagesListController(
//            userID: userID1,
//            hostID: hostID,
//            chatID: chatID,
//            unread: nil,
//            messages: [
//                messageRow(
//                    chatID: chatID,
//                    sender: userID2,
//                    senderName: "Bob",
//                    reference: ID.random.uuid,
//                    referenceName: "Alice",
//                    referenceContent: "Yeah that's what I mean",
//                    text: "I was thinking the same"
//                )
//            ],
//            scroll: .constant(nil),
//            action: { _ in },
//            loadMore: {}
//        )
//    }
//}
//
//private func messageRow(chatID: ChatID, sender: UserID, senderName: String, reference: UUID?, referenceName: String?, referenceContent: String?, text: String) -> MessageRow {
//    .init(
//        message: .init(
//            serverID: UUID(),
//            roomID: chatID.uuid,
//            date: .now,
//            state: .delivered,
//            senderID: sender.uuid,
//            contentType: .text,
//            content: text
//        ),
//        member: .init(
//            userID: sender.uuid,
//            displayName: senderName,
//            isMuted: false,
//            isBlocked: false
//        ),
//        referenceID: reference,
//        reference: .init(
//            displayName: referenceName,
//            content: referenceContent ?? ""
//        )
//    )
//}
