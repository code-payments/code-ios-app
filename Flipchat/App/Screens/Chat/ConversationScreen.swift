//
//  ConversationScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-30.
//

import SwiftUI
import SwiftData
import CodeUI
import FlipchatServices

struct ConversationScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @State private var input: String = ""
    
    @State private var stream: StreamMessagesReference?
    
    @State private var messageListState = MessageList.State()
    
    @FocusState private var isEditorFocused: Bool
    
    private let userID: UserID
    private let chatID: ChatID
    private let containerViewModel: ContainerViewModel
    private let chatController: ChatController
    
    @Query private var chats: [pChat]
    
    private var chat: pChat {
        chats[0]
    }
    
    // MARK: - Init -
    
    init(userID: UserID, chatID: ChatID, containerViewModel: ContainerViewModel, chatController: ChatController) {
        self.userID = userID
        self.chatID = chatID
        self.containerViewModel = containerViewModel
        self.chatController = chatController
        
        _chats = Query(filter: #Predicate<pChat> {
            $0.serverID == chatID.data
        })
    }
    
    private func didAppear() {
        startStream()
        advanceReadPointer()
    }
    
    private func didDisappear() {
        destroyStream()
    }
    
    // MARK: - Streams -
    
    private func startStream() {
        destroyStream()
        
        var messageID: MessageID?
        if let lastMessage = chat.messages.last?.serverID {
            messageID = MessageID(data: lastMessage)
        }
        
        stream = chatController.streamMessages(chatID: chatID, messageID: messageID) { result in
            switch result {
            case .success(let messages):
                streamMessages(messages: messages)

            case .failure(let error):
                destroyStream()
                switch error {
                case .unknown:
                    break
                case .denied:
                    break
                }
                
                showError(error: error)
            }
        }
    }
    
    private func destroyStream() {
        stream?.destroy()
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                MessageList(
                    state: $messageListState,
                    chatID: chatID,
                    userID: userID,
                    hostID: UserID(data: chat.ownerUserID),
                    action: messageAction,
                    messages: chat.messagesByDate
                )
                
                inputView()
            }
        }
        .onAppear(perform: didAppear)
        .onDisappear(perform: didDisappear)
        .interactiveDismissDisabled()
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                titleItem()
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreItem()
            }
        }
    }
    
    @ViewBuilder private func inputView() -> some View {
        HStack(alignment: .bottom) {
            conversationTextView()
                .focused($isEditorFocused)
                .font(.appTextMessage)
                .foregroundColor(.backgroundMain)
                .tint(.backgroundMain)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 35, maxHeight: 95, alignment: .leading)
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
                    .padding(2)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 5)
        .padding(.bottom, 8)
        .onChange(of: isEditorFocused) { _, focused in
            if focused {
                Task {
                    try await Task.delay(milliseconds: 150)
                    scrollToBottom()
                }
            }
        }
    }
    
    @ViewBuilder private func titleItem() -> some View {
        HStack(spacing: 10) {
            GradientAvatarView(data: chatID.data, diameter: 30)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.formattedRoomNumber)
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text("\(chat.members.count) people here")
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
    
    private func messageAction(action: MessageAction) {
        switch action {
        case .copy(let text):
            copy(text: text)
            
        case .removeUser(let name, let userID, let chatID):
            banners.show(
                style: .error,
                title: "Remove \(name)?",
                description: "They will be able to rejoin after waiting an hour, but will have to pay the cover charge again",
                position: .bottom,
                actions: [
                    .destructive(title: "Remove") {
                        Task {
                            try await chatController.removeUser(userID: userID, chatID: chatID)
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
        }
    }
    
    private func copy(text: String) {
        UIPasteboard.general.string = text
    }
    
    private func sendMessage(text: String) {
        Task {
            try await chatController.sendMessage(text: text, for: chatID)
        }
        
        input = ""
        
        scrollToBottom()
    }
    
    private func streamMessages(messages: [Chat.Message]) {
        try? chatController.receiveMessages(messages: messages, for: chatID)
        
        scrollToBottom()
        advanceReadPointer()
    }
    
    private func scrollToBottom() {
        messageListState.scrollToBottom()
    }
    
    private func advanceReadPointer() {
        Task {
            try await chatController.advanceReadPointerToLatest(for: chatID)
        }
    }
    
    // MARK: - Errors -
    
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
}
