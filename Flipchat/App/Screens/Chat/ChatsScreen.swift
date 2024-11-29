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
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var sessionAuthenticator: SessionAuthenticator
    @ObservedObject private var session: Session
    @ObservedObject private var chatController: ChatController
    @ObservedObject private var viewModel: ChatViewModel
    
    @State private var debugTapCount: Int = 0
    @State private var isShowingSettings: Bool = false
    
    @Query() private var chats: [pChat]
    
//    private var sortedRooms: [pChat] {
//        unsortedRooms.sorted { lhs, rhs in
//            lhs.newestMessage?.date.timeIntervalSince1970 ?? 0 >
//            rhs.newestMessage?.date.timeIntervalSince1970 ?? 0
//        }
//    }
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, session: Session, chatController: ChatController, viewModel: ChatViewModel) {
        self.sessionAuthenticator = sessionAuthenticator
        self.session = session
        self.chatController = chatController
        self.viewModel = viewModel
        
        var query = FetchDescriptor<pChat>()
        query.fetchLimit = 250
        query.sortBy = [.init(\.roomNumber, order: .reverse)]
        query.relationshipKeyPathsForPrefetching = [\.messages, \.previewMessage]
        query.predicate = #Predicate<pChat> {
            $0.deleted == false
        }
        _chats = Query(query)
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
                            ForEach(chats) { room in
                                row(for: room)
                            }
                        } footer: {
                            CodeButton(style: .filled, title: "Join a Room") {
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
    }
    
    @ViewBuilder private func row(for chat: pChat) -> some View {
        Button {
            viewModel.selectChat(chat: chat)
            
        } label: {
            HStack(spacing: 15) {
                GradientAvatarView(data: chat.serverID.data, diameter: 50)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                            Text(chat.formattedRoomNumber)
                                .foregroundColor(.textMain)
                                .font(.appTextMedium)
                                .lineLimit(1)
                        
                        Spacer()
                        
                        if let newestMessage = chat.previewMessage {
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
                        
//                        if chat.isMuted {
//                            Image.system(.speakerSlash)
//                                .resizable()
//                                .aspectRatio(contentMode: .fit)
//                                .frame(width: 20, height: 20, alignment: .trailing)
//                                .foregroundColor(.textSecondary)
//                        }
                        
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
