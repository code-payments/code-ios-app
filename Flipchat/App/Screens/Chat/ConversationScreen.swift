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
    
    @State private var input: String = ""
    
    @State private var scrollConfiguration: ScrollConfiguration?
    
    @State private var replyMessage: MessageRow?
    
    @State private var shouldScrollOnFocus: Bool = true
    
    @State private var isShowingOpenClose: Bool = false
    
    @FocusState private var isEditorFocused: Bool
    
    private let chatID: ChatID
    private let state: AuthenticatedState
    private let container: AppContainer
    private let userID: UserID
    private let session: Session
    private let chatController: ChatController
    
    @StateObject private var updateableRoom: Updateable<RoomDescription?>
    @StateObject private var updateableUser: Updateable<MemberRow?>
    
    private var roomDescription: RoomDescription? {
        updateableRoom.value
    }
    
    private var selfUser: MemberRow? {
        updateableUser.value
    }
    
    private var isUserMuted: Bool {
        selfUser?.isMuted == true
    }
    
    private var isSelfHost: Bool {
        roomDescription?.room.ownerUserID == userID.uuid
    }
    
    private var isRoomOpen: Bool {
        roomDescription?.room.isOpen == true
    }
    
    private var canShowOpenClose: Bool {
        isSelfHost
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
                ScrollBox(color: .backgroundMain, edgePadding: 12) {
                    MessagesListController(
                        chatController: chatController,
                        userID: userID,
                        chatID: chatID,
                        scroll: $scrollConfiguration,
                        action: { action in
                            Task {
                                try await messageAction(action: action)
                            }
                        },
                        loadMore: {}
                    )
                }
                .sheet(isPresented: $chatViewModel.isShowingCreateAccountFromConversation) {
                    CreateAccountScreen(
                        storeController: state.storeController,
                        viewModel: OnboardingViewModel(
                            state: state,
                            container: container,
                            isPresenting: $chatViewModel.isShowingCreateAccountFromConversation
                        ) { [weak chatViewModel] in
                            guard let roomDescription else {
                                return
                            }
                            
                            try await chatViewModel?.attemptJoinChat(
                                chatID: chatID,
                                hostID: UserID(uuid: roomDescription.room.ownerUserID),
                                amount: roomDescription.room.cover
                            )
                        }
                    )
                }
                
                // Bottom control
                
                if isUserMuted {
                    mutedView()
                    
                } else if !isRoomOpen && !isSelfHost {
                    roomClosedView()
                    
                } else {
                    
                    if chatController.isRegistered && selfUser?.canSend == true {
                        VStack(spacing: 0) {
                            if isShowingOpenClose {
                                openCloseView(isOpen: isRoomOpen)
                                    .transition(.move(edge: .bottom))
                            }
                            inputView()
                        }
                    } else {
                        CodeButton(
                            style: .filled,
                            title: "Pay to Chat: \(roomDescription?.room.cover.formattedTruncatedKin() ?? "")"
                        ) {
                            Task { [weak chatViewModel] in
                                guard let roomDescription else {
                                    return
                                }
                                
                                try await chatViewModel?.attemptJoinChat(
                                    chatID: ChatID(uuid: roomDescription.room.serverID),
                                    hostID: UserID(uuid: roomDescription.room.ownerUserID),
                                    amount: roomDescription.room.cover
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                }
            }
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
    }
    
    @ViewBuilder private func inputView() -> some View {
        VStack(alignment: .leading) {
            if let replyMessage {
                MessageReplyBanner(
                    name: replyMessage.member.displayName ?? "Unknown",
                    content: replyMessage.message.content
                ) {
                    self.replyMessage = nil
                }
            }
            HStack(alignment: .bottom) {
                conversationTextView()
                    .focused($isEditorFocused)
                    .font(.appTextMessage)
                    .foregroundColor(.backgroundMain)
                    .tint(.backgroundMain)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 36, maxHeight: 95, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
                    .background(.white)
                    .cornerRadius(20)
                
                Button {
                    sendMessage(text: input)
                } label: {
                    Image.asset(.paperplane)
                        .resizable()
                        .frame(width: 36, height: 36, alignment: .center)
                }
                .disabled(input.isEmpty)
            }
            .padding(.horizontal, 15)
            .padding(.top, 5)
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.2), value: replyMessage)
        .onChange(of: isEditorFocused) { _, focused in
            if focused, shouldScrollOnFocus {
                Task {
                    try await Task.delay(milliseconds: 250)
                    scrollToBottom(animated: true)
                }
            }
            
            setOpenClose(visible: !focused, animated: true)
            
            // Reset to default
            Task {
                shouldScrollOnFocus = true
            }
        }
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
            Text("The host has temporarily closed this room. Only they can send messages until they reopen it")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }
    
    @ViewBuilder private func openCloseView(isOpen: Bool) -> some View {
        HStack {
            Text("Your room is currently \(isOpen ? "open" : "closed")")
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
                    title = "Close Room Temporarily?"
                    description = "Only you will be able to send messages until you reopen the room."
                    actionTitle = "Close Temporarily"
                    action = {
                        changeRoomOpenState(open: false)
                    }
                } else {
                    title = "Reopen Room?"
                    description = "People will be able to send messages again"
                    actionTitle = "Reopen Room"
                    action = {
                        changeRoomOpenState(open: true)
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
        HStack(spacing: 10) {
            GradientAvatarView(data: chatID.data, diameter: 30)
            
            if let roomDescription = updateableRoom.value {
                VStack(alignment: .leading, spacing: 0) {
                    Text(roomDescription.room.formattedTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.appTextMedium)
                        .foregroundColor(.textMain)
                    
                    Text("\(roomDescription.memberCount) \(subtext(for: roomDescription.memberCount)) here")
                        .lineLimit(1)
                        .font(.appTextHeading)
                        .foregroundColor(.textSecondary)
                }
            }
            
            Spacer()
        }
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
    
    @ViewBuilder private func conversationTextView() -> some View {
        if #available(iOS 16.0, *) {
            TextEditor(text: $input)
                .backportScrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.never)
        } else {
            TextEditor(text: $input)
                .backportScrollContentBackground(.hidden)
        }
    }
    
    // MARK: - Actions -
    
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
            replyMessage = messageRow
            shouldScrollOnFocus = false
            isEditorFocused = true
            
        case .linkTo(let roomNumber):
            chatViewModel.previewChat(
                roomNumber: roomNumber,
                showSuccess: false,
                showModally: true
            )
        }
    }
    
    private func subtext(for count: Int?) -> String {
        if count == 1 {
            return "person"
        } else {
            return "people"
        }
    }
    
    private func copy(text: String) {
        UIPasteboard.general.string = text
    }
    
    private func changeRoomOpenState(open: Bool) {
        Task {
            try await chatController.changeRoomOpenState(chatID: chatID, open: open)
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
            
            input = ""
            replyMessage = nil
            
            try await Task.delay(milliseconds: 150)
            
            scrollToBottom(animated: true)
        }
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
