//
//  ConversationScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-30.
//

import SwiftUI
import CodeUI
import CodeServices

struct ConversationScreen: View {

    @ObservedObject var chat: Chat
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @State private var input: String = ""
    
    @State private var showingTips: Bool = false
    
    @State private var isShowingRevealIdentity: Bool = false
    
    @State private var stream: ChatMessageStreamReference?
    
    @State private var messageListState = MessageList.State()
    
    @FocusState private var isEditorFocused: Bool
    
    private let chatController: ChatController
    
    @StateObject private var viewModel: ChatViewModel
    
    // MARK: - Init -
    
    init(chat: Chat, chatController: ChatController, viewModel: @autoclosure @escaping () -> ChatViewModel) {
        self.chat = chat
        self.chatController = chatController
        self._viewModel = StateObject(wrappedValue: viewModel())
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
        guard let selfMember = chat.selfMember else {
            return
        }
        
        stream = chatController.openChatStream(chatID: chat.id, memberID: selfMember.id) { result in
            switch result {
            case .success(let events):
                streamUpdate(events: events)
                
            case .failure(let error):
                destroyStream()
                switch error {
                case .unknown:
                    break
                case .chatNotFound:
                    break
                case .denied:
                    break
                }
                // TODO: Show error
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
                if isShowingRevealIdentity {
                    RevealIdentityBanner {
                        isShowingRevealIdentity.toggle()
                    }
                }
                
                MessageList(
                    chat: chat,
                    exchange: exchange,
                    state: $messageListState,
                    delegate: viewModel
                )
                
                if chat.kind == .twoWay {
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
                    .onChange(of: isEditorFocused) { focused in
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                title()
            }
        }
    }
    
    @ViewBuilder private func title() -> some View {
        if chat.kind == .twoWay {
            HStack(spacing: 10) {
                AvatarView(value: .placeholder, diameter: 30)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(chat.displayName)
                        .font(.appTextMedium)
                        .foregroundColor(.textMain)
//                    Text("Last seen recently")
//                        .font(.appTextHeading)
//                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
            }
        } else {
            Text(chat.title)
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
        guard let selfMember = chat.selfMember else {
            return
        }
        
        Task {
            try await chatController.send(
                content: .text(text),
                in: chat,
                from: selfMember
            )
        }
        
        input = ""
    }
    
    private func streamUpdate(events: [Chat.Event]) {
        for event in events {
            switch event {
            case .message(let message):
                trace(.receive, components: "Message: \(message.id.data.hexEncodedString())", "Text: \(message.contents.map { $0.localizedText }.joined(separator: " | "))")
                let newCount = chat.insertMessages([message])
                if newCount > 0 {
                    scrollToBottom()
                    advanceReadPointer()
                }
                
            case .pointer(let pointer):
                chat.setPointer(pointer)
                trace(.receive, components: "Pointer \(pointer.kind) pointer to: \(pointer.messageID.data.hexEncodedString())")
            }
        }
    }
    
    private func scrollToBottom() {
        messageListState.scrollToBottom = true
    }
}

//#Preview {
//    ConversationScreen(chat: .mock, owner: .mock)
//        .environmentObjectsForSession()
//}