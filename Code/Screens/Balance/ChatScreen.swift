//
//  ChatScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-10-19.
//

import SwiftUI
import CodeUI
import CodeServices

struct ChatScreen: View {
    
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var notificationController: NotificationController
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @ObservedObject private var chat: Chat
    @ObservedObject private var historyController: HistoryController
    
    // MARK: - Init -
    
    init(chat: Chat, historyController: HistoryController) {
        self.chat = chat
        self.historyController = historyController
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
                try await historyController.advanceReadPointer(for: chat)
            }
        }
    }
    
    private func fetchAllMessages() {
        historyController.fetchChats()
    }
    
    @State private var isShowingConversation: Bool = false
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Flow(isActive: $isShowingConversation) {
                    ConversationScreen(
                        chatID: chat.id,
                        owner: historyController.owner
                    )
                }
                
                MessageList(
                    messages: chat.messages,
                    exchange: exchange,
                    useV2: betaFlags.hasEnabled(.alternativeBubbles),
                    showThank: betaFlags.hasEnabled(.conversations)
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
        .navigationBarTitle(Text(chat.localizedTitle))
        .if(betaFlags.hasEnabled(.conversations)) { $0
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingConversation.toggle()
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
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
            try await historyController.setMuted(muted, for: chat)
        }
    }
    
    private func setSubscriptionState() {
        Task {
            try await historyController.setSubscribed(!chat.isSubscribed, for: chat)
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
            title = Localized.Prompt.Title.mute(chat.localizedTitle)
            description = Localized.Prompt.Description.mute(chat.localizedTitle)
            action = Localized.Action.mute
        } else {
            title = Localized.Prompt.Title.unmute(chat.localizedTitle)
            description = Localized.Prompt.Description.unmute(chat.localizedTitle)
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
                title: Localized.Prompt.Title.unsubscribe(chat.localizedTitle),
                description: Localized.Prompt.Description.unsubscribe(chat.localizedTitle),
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
        title: .domain(Domain("wsj.com")!),
        pointer: .unknown,
        unreadCount: 0,
        canMute: false,
        isMuted: false,
        canUnsubscribe: true,
        isSubscribed: false,
        isVerified: false,
        messages: [
            Chat.Message(
                id: .mock2,
                date: .now.adding(days: -1),
                isReceived: nil,
                contents: [
                    .localized("A tranquil lake sits in a verdant valley, reflecting the blue sky. Lush forests surround it, alive with the sounds of nature."),
                    .kin(
                        .exact(KinAmount(
                            fiat: 5.00,
                            rate: Rate(fx: 0.000014, currency: .usd)
                        )), .received
                    ),
                ]
            ),
            Chat.Message(
                id: .mock3,
                date: .now,
                isReceived: nil,
                contents: [
                    .localized("As the sun sets in the desert, golden light bathes the sand dunes. Wind shapes the landscape, ever-changing and mesmerizing."),
                    .localized("In a cozy village, homes with thatched roofs dot the landscape. Community life thrives, marked by shared traditions and simple joys."),
                    .kin(
                        .exact(KinAmount(
                            fiat: 5.00,
                            rate: Rate(fx: 0.000014, currency: .usd)
                        )), .received
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
                    historyController: .mock
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .environmentObjectsForSession()
    }
}
