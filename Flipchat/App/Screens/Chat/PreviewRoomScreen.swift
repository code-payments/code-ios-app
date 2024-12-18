//
//  PreviewRoomScreen.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct PreviewRoomScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel

    private let chat: Chat.Metadata
    private let members: [Chat.Member]
    private let host: Chat.Identity
    private let isModal: Bool
    
    // MARK: - Init -
    
    init(chat: Chat.Metadata, members: [Chat.Member], host: Chat.Identity, viewModel: ChatViewModel, isModal: Bool) {
        self.chat = chat
        self.members = members
        self.host = host
        self.viewModel = viewModel
        self.isModal = isModal
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    AspectRatioCard {
                        VStack {
                            Spacer()
                            Image(with: .brandLarge)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 50)
                            Spacer()
                            Text("Room \(chat.roomNumber.roomString)")
                                .font(.appDisplaySmall)
                            
                            Spacer()
                            VStack(spacing: 4) {
                                Text("Hosted by \(host.displayName ?? "Member")")
                                Text("\(members.count) \(members.count == 1 ? "person" : "people") here")
                                Text("Cover Charge: ⬢ \(chat.coverAmount.formattedTruncatedKin())")
                            }
                            .opacity(0.8)
                            .font(.appTextSmall)
                            Spacer()
                        }
                        .shadow(color: Color.black.opacity(0.2), radius: 1, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            DeterministicGradient(data: chat.id.data)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    
                    Spacer()
                    
                    CodeButton(
                        state: viewModel.buttonStateWatchChat,
                        style: .filled,
                        title: "Watch Room"
                    ) {
                        Task {
                            try await viewModel.watchChat(chatID: chat.id)
                        }
                    }
                }
                .padding(20)
            }
            .foregroundColor(.textMain)
            .sheet(isPresented: $viewModel.isShowingJoinPayment) {
                PartialSheet {
                    ModalPaymentConfirmation(
                        amount: chat.coverAmount.formattedFiat(rate: .oneToOne, truncated: true, showOfKin: true),
                        currency: .kin,
                        primaryAction: "Swipe to Pay",
                        secondaryAction: "Cancel",
                        paymentAction: {
                            try await viewModel.payAndJoinChat(
                                chatID: chat.id,
                                hostID: chat.ownerUser,
                                amount: chat.coverAmount
                            )
                        },
                        dismissAction: { viewModel.pushJoinedChat(chatID: chat.id) },
                        cancelAction: { viewModel.cancelJoinChatPayment() }
                    )
                }
            }
        }
        .if(isModal) { $0
            .wrapInNavigation {
                viewModel.dismissPreviewChatModal()
            }
        }
    }
    
    private func onAppear() {
        
    }
}

#Preview {
    PreviewRoomScreen(
        chat: Chat.Metadata(
            id: .mock5,
            kind: .group,
            roomNumber: 1,
            ownerUser: .mock1,
            coverAmount: 100,
            title: "",
            unreadCount: 0,
            hasMoreUnread: false,
            isMuted: false,
            canMute: false
        ),
        members: [],
        host: .init(displayName: "Bob", avatarURL: nil),
        viewModel: .mock,
        isModal: false
    )
}
