//
//  ChatsScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-08-20.
//

import SwiftUI
import CodeUI
import CodeServices

struct ChatsScreen: View {
    
    @Binding public var isPresented: Bool
    
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var notificationController: NotificationController
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @ObservedObject private var session: Session
    @ObservedObject private var chatController: ChatController
    @ObservedObject private var bannerController: BannerController
    
    private var chats: [Chat] {
        chatController.chats
    }
    
    @StateObject private var viewModel: DirectMessageViewModel
    
    // MARK: - Init -
    
    init(session: Session, chatController: ChatController, bannerController: BannerController, isPresented: Binding<Bool>) {
        self.session = session
        self.chatController = chatController
        self.bannerController = bannerController
        self._isPresented = isPresented
        self._viewModel = StateObject(
            wrappedValue: DirectMessageViewModel(
                chatController: chatController,
                twitterController: session.twitterUserController,
                bannerController: bannerController
            )
        )
    }
    
    private func didAppear() {
        fetchAllMessages()
    }
    
    private func didDisappear() {
        
    }
    
    private func fetchAllMessages() {
        chatController.fetchChats()
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
                    
                    CodeButton(style: .filled, title: "Start a New Chat") {
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
                .onChange(of: notificationController.messageReceived) { _ in
                    didAppear()
                }
                .navigationBarHidden(false)
                .navigationBarTitle(Text(Localized.Action.chat))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $isPresented)
                    }
                }
            }
            .navigationDestination(for: DirectMessagePath.self) { path in
                switch path {
                case .enterUsername:
                    EnterUsernameScreen(viewModel: viewModel)
                case .chatUnpaid(let user):
                    DirectMessageScreen(state: .unpaid(user))
                case .chatPaid(let chat):
                    DirectMessageScreen(state: .paid(chat, chatController))
                }
            }
        }
    }
    
    @ViewBuilder private func chatsView() -> some View {
        ForEach(chats, id: \.id) { chat in
            NavigationLink {
                LazyView (
                    DirectMessageScreen(state: .paid(chat, chatController))
                )
            } label: {
                let isUnread = !chat.isMuted && chat.unreadCount > 0
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(chat.title)
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
                .padding([.trailing, .top, .bottom], 20)
                .vSeparator(color: .rowSeparator)
                .padding(.leading, 20)
            }
        }
    }
}

// MARK: - Previews -

#Preview {
    ChatsScreen(
        session: .mock,
        chatController: .mock,
        bannerController: .mock,
        isPresented: .constant(true)
    )
}
