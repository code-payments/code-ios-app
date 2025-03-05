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
    
    @State private var listenerMessage: ListenerMessage?
    
    @State private var tipUsers: TipUsers?
    
    @State private var messageTip: MessageTip?
    
    @State private var userProfileID: UserID?
    
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
        (chatController.isRegistered && canSend) || chatViewModel.isShowingInputForPaidMessage
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
                        descriptionView: descriptionView,
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
            .animation(.easeInOut(duration: 0.2), value: chatViewModel.isShowingInputForPaidMessage)
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
                    style: .filled,
                    title: "Listener Message: \(messageCost.formattedTruncatedKin())",
                    action: messageAsListenerAction
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
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
    
//    @ViewBuilder private func inputView() -> some View {
//        VStack(alignment: .leading) {
////            if let replyMessage {
////                MessageReplyBanner(
////                    name: replyMessage.member.displayName ?? "Unknown",
////                    content: replyMessage.message.content
////                ) {
////                    self.replyMessage = nil
////                }
////            }
//            
////            if isShowingOpenClose {
////                openCloseView(isOpen: isRoomOpen)
////                    .transition(.move(edge: .bottom))
////            }
//            
//            HStack(alignment: .top) {
//                TextEditor(text: $input)
//                    .backportScrollContentBackground(.hidden)
////                    .scrollDismissesKeyboard(.never)
//                    .focused($isEditorFocused)
//                    .font(.appTextMessage)
//                    .foregroundColor(.backgroundMain)
//                    .tint(.backgroundMain)
//                    .multilineTextAlignment(.leading)
//                    .frame(minHeight: 36, maxHeight: 95, alignment: .leading)
//                    .fixedSize(horizontal: false, vertical: true)
//                    .padding(.horizontal, 5)
//                    .background(.white)
//                    .cornerRadius(20)
//                    .ignoresSafeArea(.keyboard)
//                
//                Button {
//                    messageAction(text: input)
//                } label: {
//                    Image.asset(.paperplane)
//                        .resizable()
//                        .frame(width: 36, height: 36, alignment: .center)
//                }
//                .disabled(input.isEmpty)
//            }
//            .padding(.horizontal, 15)
//            .padding(.top, 5)
//            .padding(.bottom, 8)
//        }
////        .animation(.easeInOut(duration: 0.2), value: isShowingOpenClose)
//        .onChange(of: isEditorFocused) { _, focused in
////            if focused, shouldScrollOnFocus {
////                Task {
////                    try await Task.delay(milliseconds: 250)
////                    scrollToBottom(animated: true)
////                }
////            }
//            
//            if !focused && chatViewModel.isShowingInputForPaidMessage {
//                chatViewModel.isShowingInputForPaidMessage = false
//            }
//            
//            setOpenClose(visible: !focused, animated: true)
//            
//            // Reset to default
//            Task {
//                shouldScrollOnFocus = true
//            }
//        }
//        .frame(height: 50)
//        .background(.green)
//    }
    
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
            containerViewModel.pushDetails(chatID: chatID)
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
            containerViewModel.pushDetails(chatID: chatID)
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
    
    private func dismissMessagePayment(cancelled: Bool) {
        listenerMessage = nil
        
        // The "pay to message" button move the table view up
        // so we need to scroll to bottom to realign the edge
        scrollConfiguration = .init(destination: .bottom, animated: true)
        
        if cancelled {
            chatViewModel.isShowingInputForPaidMessage = true
            focusConfiguration = .init(focused: true)
        }
    }
    
    private func messageAction(action: MessageAction) async throws {
        switch action {
        case .copy(let text):
            copy(text: text)
            
        case .muteUser(let name, let userID, let chatID):
            
            // Gives the context menu time to animate
            try await Task.delay(milliseconds: 200)
            
            banners.show(
                style: .error,
                title: "Mute \(name)?",
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
            
        case .setUserBlocked(let name, let userID, _, let isBlocked):
            
            // Gives the context menu time to animate
            try await Task.delay(milliseconds: 200)
            
            let title: String
            let description: String
            
            if isBlocked {
                title = "Block \(name)?"
                description = "All messages from this user will be hidden"
            } else {
                title = "Unblock \(name)?"
                description = "All messages from this user will be visible again"
            }
            
            banners.show(
                style: .error,
                title: title,
                description: description,
                position: .bottom,
                actions: [
                    .destructive(title: title) {
                        Task {
                            try await chatController.setUserBlocked(userID: userID, blocked: isBlocked)
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
            
        case .deleteMessage(let messageID, let chatID):
            
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
                            try await chatController.deleteMessage(messageID: messageID, for: chatID)
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
            
        case .reportMessage(let userID, let messageID):
            
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
                            try await chatController.reportMessage(userID: userID, messageID: messageID)
                            showReportSuccess()
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
            
        case .reply(let messageRow):
            if !isInputVisible {
                messageAsListenerAction()
            }
            
            replyMessage = messageRow
            shouldScrollOnFocus = false
            focusConfiguration = .init(focused: true)
            
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
            
        case .promoteUser(let name, let userID, let chatID):
            focusConfiguration = .init(focused: false)
            
            // Gives the context menu time to animate
            try await Task.delay(milliseconds: 200)
            
            banners.show(
                style: .notification,
                title: "Make \(name) a Speaker?",
                description: "They will be able to message for free",
                position: .bottom,
                actions: [
                    .standard(title: "Make a Speaker") {
                        Task {
                            try await chatController.promoteUser(userID: userID, chatID: chatID)
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
            
        case .demoteUser(let name, let userID, let chatID):
            focusConfiguration = .init(focused: false)
            
            // Gives the context menu time to animate
            try await Task.delay(milliseconds: 200)
            
            banners.show(
                style: .notification,
                title: "Remove \(name) as a Speaker?",
                description: "They will no longer be able to message for free",
                position: .bottom,
                actions: [
                    .standard(title: "Remove as Speaker") {
                        Task {
                            try await chatController.demoteUser(userID: userID, chatID: chatID)
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
            
        case .openProfile(let userID):
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
    
    private func messageAction(text: String) -> Bool {
        if chatViewModel.isShowingInputForPaidMessage {
            listenerMessage = .init(text: text)
            focusConfiguration = .init(focused: false)
            return false
        } else {
            sendMessage(text: text)
            return true
        }
    }
    
    private func messageAsListenerAction() {
        chatViewModel.attemptPayForMessage {
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
            try await chatViewModel.solicitMessage(
                text: text,
                chatID: chatID,
                hostID: UserID(uuid: roomHostID),
                amount: messageCost
            )
            
//            clearInput()
            
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
            
//            clearInput()
            
            try await Task.delay(milliseconds: 150)
            
            scrollToBottom(animated: true)
        }
    }
    
//    private func clearInput() {
//        input = ""
//        replyMessage = nil
//    }
    
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
        if chatViewModel.isShowingInputForPaidMessage {
            chatViewModel.isShowingInputForPaidMessage = false
        }
    }
    
    func messageListControllerWillSendMessage(text: String) -> Bool {
        messageAction(text: text)
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
