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
    
    @ObservedObject private var historyController: HistoryController
    
    private let chat: Chat
    
    // MARK: - Init -
    
    init(chat: Chat, historyController: HistoryController) {
        self.chat = chat
        self.historyController = historyController
    }
    
    private func didAppear() {
        advanceReadPointer()
    }
    
    private func advanceReadPointer() {
        if chat.unreadCount > 0 {
            Task {
                try await historyController.advanceReadPointer(for: chat)
            }
        }
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                MessageList(messages: chat.messages, exchange: exchange)
                
                if chat.canMute || chat.canUnsubscribe {
                    HStack(spacing: 0) {
                        if chat.canMute {
                            VStack {
                                button(title: muteTitle(), action: muteAction)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
                        if chat.canUnsubscribe {
                            VStack {
                                button(title: Localized.Action.unsubscribe) {}
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
        }
        .navigationBarHidden(false)
        .navigationBarTitle(Text(chat.localizedTitle))
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
    
    // MARK: - Mute -

    private func muteTitle() -> String {
        if chat.isMuted {
            return Localized.Action.unmute
        } else {
            return Localized.Action.mute
        }
    }
    
    // MARK: - Actions -
    
    private func muteAction() {
        let action = chat.isMuted ? Localized.Action.unmute : Localized.Action.mute
        let inverseAction = chat.isMuted ? Localized.Action.mute : Localized.Action.unmute
        
        let description: String
        if chat.isMuted { 
            description = "You will be notified of any new messages from \(chat.localizedTitle). You can \(inverseAction) at any time."
        } else {
            description = "You will not be notified of any new messages from \(chat.localizedTitle). You can \(inverseAction) at any time."
        }
        
        bannerController.show(
            style: .error,
            title: "\(action) \(chat.localizedTitle)?",
            description: description,
            position: .bottom,
            isDismissable: false,
            actions: [
                .destructive(title: action, action: muteChat),
                .cancel(title: Localized.Action.cancel),
            ]
        )
    }
    
    private func muteChat() {
        Task {
            try await historyController.setMuted(!chat.isMuted, for: chat)
        }
    }
}

// MARK: - Previews -

struct ChatScreen_Previews: PreviewProvider {
    
    private static let chat = Chat(
        id: .mock,
        cursor: .mock1,
        title: .domain("wsj.com"),
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
