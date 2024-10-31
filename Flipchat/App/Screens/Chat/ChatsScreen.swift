//
//  ChatsScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-08-20.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct ChatsScreen: View {
    
    @EnvironmentObject private var notificationController: NotificationController
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @ObservedObject private var session: Session
    @ObservedObject private var sessionAuthenticator: SessionAuthenticator
    @ObservedObject private var exchange: Exchange
    @ObservedObject private var chatController: ChatController
    @ObservedObject private var bannerController: BannerController
    
    private var chats: [Chat] {
        chatController.chats
    }
    
    @StateObject private var viewModel: ChatViewModel
    
    // MARK: - Init -
    
    init(session: Session, sessionAuthenticator: SessionAuthenticator, client: FlipchatClient, exchange: Exchange, bannerController: BannerController) {
        self.session = session
        self.sessionAuthenticator = sessionAuthenticator
        self.exchange = exchange
        self.chatController = session.chatController
        self.bannerController = bannerController
        self._viewModel = StateObject(
            wrappedValue: ChatViewModel(
                session: session,
                sessionAuthenticator: sessionAuthenticator,
                client: client,
                exchange: exchange,
                bannerController: bannerController
            )
        )
    }
    
    private func didAppear() {
        
    }
    
    private func didDisappear() {
        
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    ScrollBox(color: .backgroundMain) {
                        LazyTable(
                            contentPadding: .scrollBox,
                            content: {
                                chatsView()
                            }
                        )
                    }
                    
                    CodeButton(style: .filled, title: "Join a Chat") {
                        viewModel.joinExistingChat()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    
                    CodeButton(style: .filled, title: "Create a New Room") {
                        viewModel.startNewChat()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .onAppear {
                    didAppear()
                }
                .onDisappear {
                    didDisappear()
                }
                .onChange(of: notificationController.messageReceived) {
                    didAppear()
                }
                .navigationBarHidden(false)
                .navigationBarTitle(Text(Localized.Action.chat))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            viewModel.logout()
//                            bannerController.show(
//                                style: .warning,
//                                title: "Log out?",
//                                description: "Are you sure you want to logout?",
//                                actions: [
//                                    .cancel(title: Localized.Action.ok),
//                                ]
//                            )
                        } label: {
                            Image(systemName: "door.right.hand.open")
                                .padding(5)
                        }
                    }
                }
            }
            .navigationDestination(for: DirectMessagePath.self) { path in
                switch path {
                case .enterRoomNumber:
                    EnterRoomNumberScreen(viewModel: viewModel)
                case .chat:
                    ConversationContainer(
                        chatController: chatController,
                        viewModel: viewModel
                    )
                }
            }
        }
    }
    
    @ViewBuilder private func chatsView() -> some View {
        ForEach(chats, id: \.id) { chat in
            Button {
                viewModel.selectChat(chat)
                
            } label: {
                let isUnread = !chat.isMuted && chat.unreadCount > 0
                
                HStack(spacing: 15) {
                    AvatarView(value: avatarValue(for: chat), diameter: 50)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 10) {
                            Text(chat.displayName)
                                .foregroundColor(.textMain)
                                .font(.appTextMedium)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if let newestMessage = chat.newestMessage {
                                Text(newestMessage.date.formattedRelatively(useTimeForToday: true))
                                    .foregroundColor(isUnread ? .textSuccess : .textSecondary)
                                    .font(.appTextSmall)
                                    .lineLimit(1)
                            }
                        }
                        .frame(height: 23) // Ensures the same height with and without Bubble
                        
                        HStack(alignment: .top, spacing: 5) {
                            Text(chat.previewMessage)
                                .foregroundColor(.textSecondary)
                                .font(.appTextMedium)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            if chat.isMuted {
                                Image.system(.speakerSlash)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20, alignment: .trailing)
                                    .foregroundColor(.textSecondary)
                            }
                            
                            if isUnread {
                                Bubble(size: .large, count: chat.unreadCount)
                            }
                        }
                    }
                }
                .padding([.trailing, .top, .bottom], 20)
                .vSeparator(color: .rowSeparator)
                .padding(.leading, 20)
            }
        }
    }
    
    private func avatarValue(for chat: Chat) -> AvatarView.Value {
        .placeholder
    }
}

// MARK: - Previews -

#Preview {
    ChatsScreen(
        session: .mock,
        sessionAuthenticator: .mock,
        client: .mock,
        exchange: .mock,
        bannerController: .mock
    )
}
