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
    
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var sessionAuthenticator: SessionAuthenticator
    @ObservedObject private var session: Session
    @ObservedObject private var chatController: ChatController
    @ObservedObject private var viewModel: ChatViewModel
    
    @State private var debugTapCount: Int = 0
    @State private var isShowingSettings: Bool = false
    
    @StateObject private var updateableRooms: Updateable<[RoomRow]>
    
    private let state: AuthenticatedState
    private let container: AppContainer
    private let flipClient: FlipchatClient
    private let client: Client
    
    private var rooms: [RoomRow] {
        updateableRooms.value
    }
    
    // MARK: - Init -
    
    init(state: AuthenticatedState, container: AppContainer) {
        self.state = state
        self.container = container
        self.sessionAuthenticator = container.sessionAuthenticator
        self.session = state.session
        self.chatController = state.chatController
        self.viewModel = state.chatViewModel
        self.flipClient = container.flipClient
        self.client = container.client
        
        let chatController = state.chatController
        self._updateableRooms = .init(wrappedValue: Updateable {
            (try? chatController.getRooms()) ?? []
        })
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                navigationBar()
                
                List {
                    Section {
                        ForEach(rooms) { roomRow in
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
                        CodeButton(style: .filled, title: "Find a Flipchat") {
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
        .sheet(isPresented: $isShowingSettings) {
            SettingsScreen(
                sessionAuthenticator: sessionAuthenticator,
                session: session,
                isPresented: $isShowingSettings
            )
            .environmentObject(banners)
        }
        .sheet(isPresented: $viewModel.isShowingCreateAccountFromChats) {
            CreateAccountScreen(
                storeController: state.storeController,
                viewModel: OnboardingViewModel(
                    state: state,
                    container: container,
                    isPresenting: $viewModel.isShowingCreateAccountFromChats
                ) { [weak viewModel] in
                    viewModel?.attemptCreateChat()
                }
            )
        }
        .sheet(isPresented: $viewModel.isShowingFindRoomModal) {
            PartialSheet {
                ModalButtons(
                    isPresented: $viewModel.isShowingFindRoomModal,
                    actions: [
                        .init(title: "Enter Flipchat Number") {
                            viewModel.showEnterRoomNumber()
                        },
                        .init(title: "Create New Flipchat: \(session.startGroupCost.formattedTruncatedKin())") {
                            viewModel.attemptCreateChat()
                        },
                    ]
                )
            }
        }
    }
    
    @ViewBuilder private func navigationBar() -> some View {
        NavBar(isLoading: chatController.isSyncInProgress, title: "Flipchats") {
            debugTapCount += 1
            if debugTapCount >= 7 {
                logoutAction()
                debugTapCount = 0
            }
            
        } leading: {
            if betaFlags.accessGranted {
                Button {
                    isShowingSettings = true
                } label: {
                    Image.asset(.more)
                        .padding(.vertical, 10)
                        .padding(.leading, 20)
                        .padding(.trailing, 30)
                }
                
            } else {
                NavBarEmptyItem()
            }
            
        } trailing: {
            Button {
                viewModel.startChatting()
            } label: {
                Image.asset(.plusCircle)
                    .padding(5)
            }
        }
    }
    
    @ViewBuilder private func row(for row: RoomRow) -> some View {
        Button {
            viewModel.pushChat(chatID: ChatID(uuid: row.room.serverID))
            
        } label: {
            HStack(spacing: 15) {
                GradientAvatarView(data: row.room.serverID.data, diameter: 50)
                    .if(row.room.ownerUserID == session.userID.uuid) { $0
                        .overlay {
                            Image.asset(.crown)
                                .position(x: 5, y: 5)
                        }
                    }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(row.room.formattedTitle)
                            .foregroundColor(.textMain)
                            .font(.appTextMedium)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let message = row.lastMessage {
                            Text(message.date.formattedRelatively(useTimeForToday: true))
                                .foregroundColor(row.room.unreadCount > 0 ? .textSuccess : .textSecondary)
                                .font(.appTextSmall)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 23) // Ensures the same height with and without Bubble
                    
                    HStack(alignment: .top, spacing: 5) {
                        let content = row.lastMessage?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No messages"
                        Text(content)
                            .foregroundColor(.textSecondary)
                            .font(.appTextMedium)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        HStack {
                            if row.room.isMuted {
                                Image.system(.speakerSlash)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 15, height: 15, alignment: .trailing)
                                    .foregroundColor(.textSecondary)
                            }
                            
                            if row.room.unreadCount > 0 {
                                Bubble(
                                    size: .large,
                                    count: row.room.unreadCount,
                                    hasMore: row.room.hasMoreUnread
                                )
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
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
        state: .mock,
        container: .mock
    )
}
