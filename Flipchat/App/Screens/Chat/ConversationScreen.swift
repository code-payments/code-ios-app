//
//  ConversationScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-30.
//

import SwiftUI
import CodeUI
import CodeServices
import FlipchatServices

struct ConversationScreen: View {

    @ObservedObject var chat: Chat
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var bannerController: BannerController
    
    @State private var input: String = ""
    
    @State private var stream: StreamMessagesReference?
    
    @State private var messageListState = MessageList.State()
    
    @FocusState private var isEditorFocused: Bool
    
    private let chatController: ChatController
    
    private var avatarValue: AvatarView.Value {
        .placeholder
    }
    
    // MARK: - Init -
    
    init(chat: Chat, chatController: ChatController) {
        self.chat = chat
        self.chatController = chatController
    }
    
    private func didAppear() {
        startStream()
        advanceReadPointer()
    }
    
    private func didDisappear() {
        destroyStream()
    }
    
    private func advanceReadPointer() {
        Task {
            try await chatController.advanceReadPointer(for: chat)
        }
    }
    
    // MARK: - Streams -
    
    private func startStream() {
        stream = chatController.streamMessages(chatID: chat.id) { result in
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
                    chat: chat,
                    exchange: exchange,
                    state: $messageListState
                )
                
                if chat.kind == .twoWay || chat.kind == .group {
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
                                try await Task.delay(milliseconds: 50)
                                scrollToBottom()
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: didAppear)
        .onDisappear(perform: didDisappear)
        .interactiveDismissDisabled()
        .navigationBarHidden(false)
    }
    
    @ViewBuilder private func title() -> some View {
        if chat.kind == .twoWay {
            HStack(spacing: 10) {
                AvatarView(value: avatarValue, diameter: 30)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(chat.displayName)
                        .font(.appTextMedium)
                        .foregroundColor(.textMain)
                    Text("Last seen recently")
                        .font(.appTextHeading)
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
            }
        } else {
            Text(chat.displayName)
                .font(.appTitle)
                .foregroundColor(.textMain)
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
            try await chatController.sendMessage(content: .text(text), in: chat.id)
        }
        
        input = ""
    }
    
    private func streamMessages(messages: [Chat.Message]) {
        chat.insertMessages(messages)
    }
    
    private func scrollToBottom() {
        messageListState.scrollToBottom = true
    }
    
    // MARK: - Errors -
    
    private func showError(error: Error) {
        bannerController.show(
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
