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
                
                HStack(spacing: 0) {
//                    Button {} label: {
//                        Text("Mute")
//                            .frame(maxWidth: .infinity)
//                            .font(.appTextMedium)
//                            .foregroundStyle(Color.backgroundMain)
//                            .padding(.vertical, 15)
//                            .padding(.horizontal, 30)
//                            .background(.white)
//                            .cornerRadius(999)
//                    }
//                    
//                    Button {} label: {
//                        Text("Unsubscribe")
//                            .frame(maxWidth: .infinity)
//                            .font(.appTextMedium)
//                            .foregroundStyle(Color.backgroundMain)
//                            .padding(.vertical, 15)
//                            .padding(.horizontal, 30)
//                            .background(.white)
//                            .cornerRadius(999)
//                    }
                    
//                    CodeButton(style: .filled, title: "Mute"/*, disabled: !chat.canMute*/) {}
//                    CodeButton(style: .filled, title: "Unsubscribe"/*, disabled: !chat.canUnsubscribe*/) {}
                    VStack {
                        Button {} label: {
                            Text("Mute")
                                .frame(maxWidth: .infinity)
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                                .padding(.vertical, 15)
                                .padding(.horizontal, 30)
                                .background(Color.white.opacity(0.01))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .hSeparator(color: .rowSeparator, position: .trailing)
                    
                    VStack {
                        Button {} label: {
                            Text("Unsubscribe")
                                .frame(maxWidth: .infinity)
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                                .padding(.vertical, 15)
                                .padding(.horizontal, 30)
                                .background(Color.white.opacity(0.01))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 60)
//                .padding(.vertical, 10)
//                .padding(.horizontal, 20)
                .vSeparator(color: .rowSeparator, position: .top)
            }
            .onAppear {
                didAppear()
            }
        }
        .navigationBarHidden(false)
        .navigationBarTitle(Text(chat.localizedTitle))
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
