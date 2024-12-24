//
//  ConversationScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-30.
//

import SwiftUI
import CodeUI
import FlipchatServices

//@MainActor
//private class ConversationState: ObservableObject {
//    
//    let pointer: MessagePointer? // We don't want to publish changes
//    
//    @Published var room: RoomDescription!
//    @Published var selfUser: MemberRow!
//    @Published var messages: [MessageRow] = []
//    
//    @Published var scrollToBottom: Int = 0
//    
//    private var pageSize: Int = 1024
//    
//    private let userID: UserID
//    private let chatID: ChatID
//    private let chatController: ChatController
//    
//    private var stream: StreamMessagesReference?
//    
//    // MARK: - Init -
//    
//    init(userID: UserID, chatID: ChatID, chatController: ChatController) throws {
//        self.userID = userID
//        self.chatID = chatID
//        self.chatController = chatController
//        
//        room     = try chatController.getRoom(chatID: chatID)
//        selfUser = try chatController.getMember(userID: userID, roomID: chatID)
//        messages = try chatController.getMessages(chatID: chatID, pageSize: pageSize)
//        
//        pointer  = try chatController.getPointer(userID: userID, chatID: chatID)
//        
//        startStream()
//    }
//    
//    deinit {
//        DispatchQueue.main.async { [stream] in
//            trace(.warning, components: "Destroying conversation stream...")
//            stream?.destroy()
//        }
//    }
//    
//    func addPageAndReload() throws {
//        pageSize += 1024
//        try reload()
//    }
//    
//    func reload() throws {
//        room     = try chatController.getRoom(chatID: chatID)
//        selfUser = try chatController.getMember(userID: userID, roomID: chatID)
//        // Don't update the pointer
//        messages = try chatController.getMessages(chatID: chatID, pageSize: pageSize)
//    }
//    
//    // MARK: - Pointer -
//    
//    private func advanceReadPointer() async throws {
//        try await chatController.advanceReadPointerToLatest(for: chatID)
//    }
//    
//    // MARK: - Streams -
//    
//    func startStream() {
//        destroyStream()
//        
//        guard let room else {
//            return
//        }
//        
//        let messageID: MessageID?
//        if let lastMessage = room.lastMessage {
//            messageID = MessageID(uuid: lastMessage.serverID)
//        } else {
//            messageID = nil
//        }
//        
//        stream = chatController.streamMessages(chatID: chatID, messageID: messageID) { [weak self] result in
//            switch result {
//            case .success(let messages):
//                self?.streamMessages(messages: messages)
//
//            case .failure:
//                self?.destroyStream()
//            }
//        }
//    }
//    
//    private func streamMessages(messages: [Chat.Message]) {
//        Task {
//            try await chatController.receiveMessages(messages: messages, for: chatID)
//            try await advanceReadPointer()
//            
//            scrollToBottom += 1
//        }
//    }
//    
//    func destroyStream() {
//        trace(.warning, components: "Destroying conversation stream...")
//        stream?.destroy()
//    }
//}

struct ConversationScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var flipClient: FlipchatClient
    @EnvironmentObject private var banners: Banners
    @EnvironmentObject private var notificationController: NotificationController
    
    @ObservedObject private var containerViewModel: ContainerViewModel
    @ObservedObject private var chatViewModel: ChatViewModel
    
    @State private var input: String = ""
    
    @State private var scrollConfiguration: ScrollConfiguration?
    
    @State private var replyMessage: MessageRow?
    
    @State private var shouldScrollOnFocus: Bool = true
    
    @FocusState private var isEditorFocused: Bool
    
    private let chatID: ChatID
    private let state: AuthenticatedState
    private let container: AppContainer
    private let userID: UserID
    private let session: Session
    private let chatController: ChatController
    
    @StateObject private var updateableRoom: Updateable<RoomDescription>
    @StateObject private var updateableUser: Updateable<MemberRow>
    
    private var roomDescription: RoomDescription {
        updateableRoom.value
    }
    
    private var selfUser: MemberRow {
        updateableUser.value
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
            try! chatController.getRoom(chatID: chatID)!
        })
        
        self._updateableUser = .init(wrappedValue: Updateable {
            try! chatController.getMember(userID: userID, roomID: chatID)!
        })
    }
    
    private func didAppear() {
        
    }
    
    private func didDisappear() {
        
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
                            try await chatViewModel?.attemptJoinChat(
                                chatID: chatID,
                                hostID: UserID(uuid: roomDescription.room.ownerUserID),
                                amount: roomDescription.room.cover
                            )
                        }
                    )
                }
                .sheet(isPresented: $chatViewModel.isShowingJoinPayment) {
                    PartialSheet {
                        ModalPaymentConfirmation(
                            amount: roomDescription.room.cover.formattedFiat(rate: .oneToOne, truncated: true, showOfKin: true),
                            currency: .kin,
                            primaryAction: "Swipe to Pay",
                            secondaryAction: "Cancel",
                            paymentAction: {
                                try await chatViewModel.payAndJoinChat(
                                    chatID: ChatID(uuid: roomDescription.room.serverID),
                                    hostID: UserID(uuid: roomDescription.room.ownerUserID),
                                    amount: roomDescription.room.cover
                                )
                            },
                            dismissAction: { chatViewModel.cancelJoinChatPayment() },
                            cancelAction:  { chatViewModel.cancelJoinChatPayment() }
                        )
                    }
                }
                .sheet(item: $chatViewModel.isShowingPreviewRoom) { preview in
                    PreviewRoomScreen(
                        chat: preview.chat,
                        members: preview.members,
                        host: preview.host,
                        viewModel: chatViewModel,
                        isModal: true
                    )
                }
                
                if chatController.isRegistered && selfUser.canSend {
                    if !selfUser.isMuted {
                        inputView()
                    } else {
                        VStack {
                            Text("You've been muted")
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(height: 50)
                    }
                } else {
                    CodeButton(
                        style: .filled,
                        title: "Join Room: ⬢ \(roomDescription.room.cover.formattedTruncatedKin())"
                    ) {
                        Task {
                            try await chatViewModel.attemptJoinChat(
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
        .onAppear(perform: didAppear)
        .onDisappear(perform: didDisappear)
        .interactiveDismissDisabled()
        .navigationBarHidden(false)
        .navigationBarTitle("", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                titleItem()
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreItem()
            }
        }
//        .onChange(of: notificationController.didBecomeActive) { _, _ in
//            conversationState.startStream()
//        }
//        .onChange(of: notificationController.willResignActive) { _, _ in
//            conversationState.destroyStream()
//        }
//        .onChange(of: chatController.chatsDidChange) { _, _ in
//            try? conversationState.reload()
//        }
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
                    //                    .padding([.bottom, .leading, .trailing], 2)
                    //                    .padding(.top, 8)
                }
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
            
            // Reset to default
            Task {
                shouldScrollOnFocus = true
            }
        }
    }
    
    @ViewBuilder private func titleItem() -> some View {
        HStack(spacing: 10) {
            GradientAvatarView(data: chatID.data, diameter: 30)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(updateableRoom.value.room.formattedTitle)
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text("\(updateableRoom.value.memberCount) \(subtext(for: updateableRoom.value.memberCount)) here")
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
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
                .padding(.leading, 40)
                .padding(.trailing, 10)
        }
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

private func messageRow(chatID: ChatID, sender: UserID, senderName: String, reference: UUID?, referenceName: String?, referenceContent: String?, text: String) -> MessageRow {
    .init(
        message: .init(
            serverID: UUID(),
            roomID: chatID.uuid,
            date: .now,
            state: .delivered,
            senderID: sender.uuid,
            contentType: .text,
            content: text
        ),
        member: .init(
            userID: sender.uuid,
            displayName: senderName,
            isMuted: false,
            isBlocked: false
        ),
        referenceID: reference,
        reference: .init(
            displayName: referenceName,
            content: referenceContent ?? ""
        )
    )
}
