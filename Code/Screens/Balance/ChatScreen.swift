//
//  ChatScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-10-19.
//

import SwiftUI
import CodeUI
import CodeServices

struct DirectMessageScreen: View {
    
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var notificationController: NotificationController
    @EnvironmentObject private var betaFlags: BetaFlags
    
    private let state: State
    
    var displayName: String {
        switch state {
        case .unpaid(let twitterUser):
            return twitterUser.displayName
        case .paid(let chat, _):
            return chat.title
        }
    }
    
    init(state: State) {
        self.state = state
    }
    
    var body: some View {
        Background(color: .backgroundMain) {
            switch state {
            case .paid(let chat, let chatController):
                ChatScreen(chat: chat, chatController: chatController)
                
            case .unpaid(let twitterUser):
                VStack {
                    Spacer()
                    
                    CodeButton(style: .filledThin, title: "Send $1.00 to Start Chatting") {
                        // Make payment
                    }
                }
                .padding(20)
            }
        }
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                title()
            }
        }
    }
    
    @ViewBuilder private func title() -> some View {
        HStack(spacing: 10) {
            AvatarView(value: .placeholder, diameter: 30)
//                GeneratedAvatarView(data: chat.id.data, diameter: 30)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                    .font(.appTextMedium)
                    .foregroundColor(.textMain)
                Text("Last seen recently")
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
        }
    }
    
    enum State {
        case unpaid(TwitterUser)
        case paid(Chat, ChatController)
    }
}

struct ChatScreen: View {
    
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var notificationController: NotificationController
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @ObservedObject private var chat: Chat
    @ObservedObject private var chatController: ChatController
    
    @State private var messageListState = MessageList.State()
    
//    @StateObject private var viewModel: ChatViewModel
    
    // MARK: - Init -
    
    init(chat: Chat, chatController: ChatController) {//}, viewModel: @autoclosure @escaping () -> ChatViewModel) {
        self.chat = chat
        self.chatController = chatController
//        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    private func didAppear() {
        advanceReadPointer()
        fetchAllMessages()
    }
    
    private func didDisappear() {
        advanceReadPointer()
    }
    
    private func advanceReadPointer() {
        if chat.unreadCount > 0 {
            Task {
                try await chatController.advanceReadPointer(for: chat)
            }
        }
    }
    
    private func fetchAllMessages() {
        chatController.fetchChats()
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                MessageList(
                    chat: chat,
                    exchange: exchange,
                    state: $messageListState
//                    delegate: viewModel
                )
                
                if chat.canMute || chat.canUnsubscribe {
                    HStack(spacing: 0) {
                        if chat.canMute {
                            VStack {
                                button(title: muteTitle(), action: setMuteStateAction)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        if chat.canUnsubscribe, betaFlags.hasEnabled(.canUnsubcribe) {
                            VStack {
                                button(title: subscriptionTitle(), action: setSubscriptionStateAction)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .hSeparator(color: .rowSeparator, position: .leading, weight: .medium)
                        }
                    }
                    .frame(height: 60)
                    .vSeparator(color: .rowSeparator, position: .top, weight: .medium)
                }
            }
            .onAppear {
                didAppear()
            }
            .onDisappear {
                didDisappear()
            }
            .onChange(of: notificationController.messageReceived) { _ in
                didAppear()
            }
        }
        .navigationBarHidden(false)
    }
    
    @ViewBuilder private func button(title: String, action: @escaping VoidAction) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .padding(.vertical, 15)
                .padding(.horizontal, 30)
        }
    }
    
    // MARK: - State -
    
    private func setMuteState(muted: Bool) {
        Task {
            try await chatController.setMuted(muted, for: chat)
        }
    }
    
    private func setSubscriptionState() {
        Task {
            try await chatController.setSubscribed(!chat.isSubscribed, for: chat)
        }
    }

    private func muteTitle() -> String {
        if chat.isMuted {
            return Localized.Action.unmute
        } else {
            return Localized.Action.mute
        }
    }
    
    private func subscriptionTitle() -> String {
        if chat.isSubscribed {
            return Localized.Action.unsubscribe
        } else {
            return Localized.Action.subscribe
        }
    }
    
    // MARK: - Actions -
    
    private func setMuteStateAction() {
        let shouldMute = !chat.isMuted
        
        let action: String
        let title: String
        let description: String
        
        if shouldMute {
            title = Localized.Prompt.Title.mute(chat.displayName)
            description = Localized.Prompt.Description.mute(chat.displayName)
            action = Localized.Action.mute
        } else {
            title = Localized.Prompt.Title.unmute(chat.displayName)
            description = Localized.Prompt.Description.unmute(chat.displayName)
            action = Localized.Action.unmute
        }
        
        bannerController.show(
            style: .error,
            title: title,
            description: description,
            position: .bottom,
            isDismissable: false,
            actions: [
                .destructive(title: action) {
                    setMuteState(muted: shouldMute)
                },
                .cancel(title: Localized.Action.cancel),
            ]
        )
    }
    
    private func setSubscriptionStateAction() {
        if chat.isSubscribed {
            bannerController.show(
                style: .error,
                title: Localized.Prompt.Title.unsubscribe(chat.displayName),
                description: Localized.Prompt.Description.unsubscribe(chat.displayName),
                position: .bottom,
                isDismissable: false,
                actions: [
                    .destructive(title: Localized.Action.unsubscribe, action: setSubscriptionState),
                    .cancel(title: Localized.Action.cancel),
                ]
            )
        } else {
            setSubscriptionState()
        }
    }
}

// MARK: - Previews -

struct ChatScreen_Previews: PreviewProvider {
    
    private static let chat = Chat(
        id: .mock,
        cursor: .mock1,
        kind: .notification,
        title: "wsj.com",
        canMute: false,
        canUnsubscribe: true,
        members: [],
        messages: [
            Chat.Message(
                id: .mock2,
                senderID: .mock2,
                date: .now.adding(days: -1),
                cursor: .mock2,
                contents: [
                    .localized("A tranquil lake sits in a verdant valley, reflecting the blue sky. Lush forests surround it, alive with the sounds of nature."),
                    .kin(
                        .exact(KinAmount(
                            fiat: 5.00,
                            rate: Rate(fx: 0.000014, currency: .usd)
                        )), .received, .mock
                    ),
                ]
            ),
            Chat.Message(
                id: .mock3,
                senderID: .mock2,
                date: .now,
                cursor: .mock2,
                contents: [
                    .localized("As the sun sets in the desert, golden light bathes the sand dunes. Wind shapes the landscape, ever-changing and mesmerizing."),
                    .localized("In a cozy village, homes with thatched roofs dot the landscape. Community life thrives, marked by shared traditions and simple joys."),
                    .kin(
                        .exact(KinAmount(
                            fiat: 5.00,
                            rate: Rate(fx: 0.000014, currency: .usd)
                        )), .received, .mock
                    ),
                ]
            )
        ]
    )
    
    static var previews: some View {
        Preview(devices: .iPhoneMax) {
            NavigationView {
                ChatScreen(
                    chat: chat,
                    chatController: .mock
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .environmentObjectsForSession()
    }
}
