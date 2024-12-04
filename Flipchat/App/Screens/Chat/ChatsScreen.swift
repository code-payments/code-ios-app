//
//  ChatsScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-08-20.
//

import SwiftUI
import CodeUI
import FlipchatServices

@MainActor
@Observable
private class ChatsState {
    
    var rooms: [RoomRow] = []
    
    private let chatController: ChatController
    
    init(chatController: ChatController) {
        self.chatController = chatController
        
        try? reload()
    }
    
    func reload() throws {
        rooms = try chatController.getRooms()
    }
}

struct ChatsScreen: View {
    
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var sessionAuthenticator: SessionAuthenticator
    @ObservedObject private var session: Session
    @ObservedObject private var chatController: ChatController
    @ObservedObject private var viewModel: ChatViewModel
    
    @State private var debugTapCount: Int = 0
    @State private var isShowingSettings: Bool = false
    
    @State private var chatState: ChatsState
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, session: Session, chatController: ChatController, viewModel: ChatViewModel) {
        self.sessionAuthenticator = sessionAuthenticator
        self.session = session
        self.chatController = chatController
        self.viewModel = viewModel
        self.chatState = .init(chatController: chatController)
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
                            ForEach(chatState.rooms) { roomRow in
                                row(for: roomRow)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .cancel) {
                                            muteChat(for: roomRow.room)
                                        } label: {
                                            if roomRow.room.isMuted {
                                                Label("", systemImage: "speaker.wave.2")
                                            } else {
                                                Label("", systemImage: "speaker.slash")
                                            }
                                        }
                                        .tint(.darkPurple)
                                    }
                            }
                        } footer: {
                            CodeButton(style: .filled, title: "Join a Room") {
                                viewModel.startChatting()
                            }
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 20)
                        }
                        .padding(.top, 5)
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
                if betaFlags.accessGranted {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image.asset(.more)
                                .padding(.vertical, 10)
                                .padding(.leading, 10)
                                .padding(.trailing, 40)
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Chats")
                        .font(.appTitle)
                        .foregroundStyle(Color.textMain)
                        .onTapGesture {
                            debugTapCount += 1
                            if debugTapCount >= 7 {
                                logoutAction()
                                debugTapCount = 0
                            }
                        }
                        .sheet(isPresented: $isShowingSettings) {
                            SettingsScreen(
                                sessionAuthenticator: sessionAuthenticator,
                                session: session,
                                isPresented: $isShowingSettings
                            )
                            .environmentObject(banners)
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
        .sheet(isPresented: $viewModel.isShowingCreatePayment) {
            PartialSheet {
                ModalPaymentConfirmation(
                    amount: session.startGroupCost.formattedFiat(rate: .oneToOne, truncated: true, showOfKin: true),
                    currency: .kin,
                    primaryAction: "Swipe to Pay",
                    secondaryAction: "Cancel",
                    paymentAction: {
                        try await viewModel.createChat()
                    },
                    dismissAction: { viewModel.isShowingCreatePayment = false },
                    cancelAction: { viewModel.isShowingCreatePayment = false }
                )
            }
        }
        .onChange(of: chatController.chatsDidChange) { _, _ in
            try? chatState.reload()
        }
    }
    
    @ViewBuilder private func row(for row: RoomRow) -> some View {
        Button {
            viewModel.selectChat(chatID: ChatID(uuid: row.room.serverID))
            
        } label: {
            HStack(spacing: 15) {
                GradientAvatarView(data: row.room.serverID.data, diameter: 50)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                            Text(row.room.roomNumber.formattedRoomNumber)
                                .foregroundColor(.textMain)
                                .font(.appTextMedium)
                                .lineLimit(1)
                        
                        Spacer()
                        
                        Text(row.lastMessage.date.formattedRelatively(useTimeForToday: true))
                            .foregroundColor(row.room.unreadCount > 0 && !row.room.isMuted ? .textSuccess : .textSecondary)
                            .font(.appTextSmall)
                            .lineLimit(1)
                    }
                    .frame(height: 23) // Ensures the same height with and without Bubble
                    
                    HStack(alignment: .top, spacing: 5) {
                        Text(row.lastMessage.contents.contentPreview)
                            .foregroundColor(.textSecondary)
                            .font(.appTextMedium)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        if row.room.isMuted {
                            Image.system(.speakerSlash)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 15, height: 15, alignment: .trailing)
                                .foregroundColor(.textSecondary)
                        } else {
                            if row.room.unreadCount > 0 {
                                Bubble(size: .large, count: row.room.unreadCount)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func avatarValue(for chat: Chat) -> AvatarView.Value {
        .placeholder
    }
    
    // MARK: - Action -
    
    private func muteChat(for room: RoomRow.Room) {
        Task {
            try await chatController.muteChat(
                chatID: ChatID(uuid: room.serverID),
                muted: !room.isMuted
            )
        }
    }
    
    private func logoutAction() {
        banners.show(
            style: .error,
            title: "Log out?",
            description: "Are you sure you want to log out?",
            position: .bottom,
            actions: [
                .destructive(title: "Log Out") {
                    sessionAuthenticator.logout()
                },
                .cancel(title: "Cancel"),
            ]
        )
    }
}

// MARK: - Previews -

#Preview {
    ChatsScreen(
        sessionAuthenticator: .mock,
        session: .mock,
        chatController: .mock,
        viewModel: .mock
    )
}
