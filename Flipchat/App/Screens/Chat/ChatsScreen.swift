//
//  ChatsScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-08-20.
//

import SwiftUI
import SwiftData
import CodeUI
import FlipchatServices

struct ChatsScreen: View {
    
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @ObservedObject private var session: Session
    @ObservedObject private var chatController: ChatController
    @ObservedObject private var viewModel: ChatViewModel
    
    @Query(
        filter: #Predicate<pChat> { $0.isHidden == false },
        sort: \pChat.id, order: .reverse
    )
    private var unsortedRooms: [pChat]
    
    private var sortedRooms: [pChat] {
        unsortedRooms.sorted { lhs, rhs in
            lhs.newestMessage?.date.timeIntervalSince1970 ?? 0 >
            rhs.newestMessage?.date.timeIntervalSince1970 ?? 0
        }
    }
    
    // MARK: - Init -
    
    init(session: Session, chatController: ChatController, viewModel: ChatViewModel) {
        self.session = session
        self.chatController = chatController
        self.viewModel = viewModel
    }
    
    private func didAppear() {
        
    }
    
    private func didDisappear() {
        
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                ScrollBox(color: .backgroundMain) {
                    List {
                        Section {
                            ForEach(sortedRooms) { room in
                                row(for: room)
                            }
                        } footer: {
                            CodeButton(style: .filled, title: "Join a Chat") {
                                viewModel.startChatting()
                            }
                            .listRowSeparator(.hidden)
                            .padding(.top, 20)
                        }
                        .listRowSeparatorTint(.rowSeparator)
                        .listRowBackground(Color.backgroundMain)
                        .scrollContentBackground(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .onAppear {
                didAppear()
            }
            .onDisappear {
                didDisappear()
            }
            .navigationBarHidden(false)
            .navigationBarTitle(Text("Chats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.logout()
                    } label: {
                        Image(systemName: "door.right.hand.open")
                            .padding(5)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.startChatting()
                    } label: {
                        Image.asset(.plusCircle)
                            .padding(5)
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingEnterRoomNumber) {
            EnterRoomNumberScreen(viewModel: viewModel)
        }
    }
    
    @ViewBuilder private func row(for chat: pChat) -> some View {
        Button {
            viewModel.selectChat(chat: chat)
            
        } label: {
            HStack(spacing: 15) {
                GradientAvatarView(data: chat.id, diameter: 50)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                            Text(chat.formattedRoomNumber)
                                .foregroundColor(.textMain)
                                .font(.appTextMedium)
                                .lineLimit(1)
                        
                        Spacer()
                        
                        if let newestMessage = chat.newestMessage {
                            Text(newestMessage.date.formattedRelatively(useTimeForToday: true))
                                .foregroundColor(chat.isUnread ? .textSuccess : .textSecondary)
                                .font(.appTextSmall)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 23) // Ensures the same height with and without Bubble
                    
                    HStack(alignment: .top, spacing: 5) {
                        Text(chat.newestMessagePreview)
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
                        
                        if chat.isUnread {
                            Bubble(size: .large, count: chat.unreadCount)
                        }
                    }
                }
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
        chatController: .mock,
        viewModel: .mock
    )
}
