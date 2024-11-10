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
    private let chatController: ChatController
    
    @Query private var chats: [pChat]
    
    private var chat: pChat {
        chats[0]
    }
    
    // MARK: - Init -
    
    init(userID: UserID, chatID: ChatID, chatController: ChatController) {
        self.userID = userID
        self.chatID = chatID
        self.chatController = chatController
        
        _chats = Query(filter: #Predicate<pChat> {
            $0.id == chatID.data
        })
    }
    
    private func didAppear() {
        startStream()
    }
    
    private func didDisappear() {
        destroyStream()
    }
    
    // MARK: - Streams -
    
    private func startStream() {
        destroyStream()
        
        stream = chatController.streamMessages(chatID: chatID) { result in
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
                    userID: userID,
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
                title()
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
        .padding(.horizontal, 10)
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
    
    @ViewBuilder private func title() -> some View {
        HStack(spacing: 10) {
            GradientAvatarView(data: chatID.data, diameter: 30)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(chat.formattedRoomNumber)
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text("Last seen recently")
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
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
    
    private func sendMessage(text: String) {
        Task {
            try await chatController.sendMessage(text: text, for: ID(data: chat.id))
        }
        
        input = ""
        
        scrollToBottom()
    }
    
    private func streamMessages(messages: [Chat.Message]) {
        try? chatController.receiveMessages(messages: messages, for: ID(data: chat.id))
        
        scrollToBottom()
    }
    
    private func scrollToBottom() {
        messageListState.scrollToBottom()
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
