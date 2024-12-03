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
    private var host: Chat.Identity
    
    // MARK: - Init -
    
    init(chat: Chat.Metadata, members: [Chat.Member], host: Chat.Identity, viewModel: ChatViewModel) {
        self.chat = chat
        self.members = members
        self.host = host
        self.viewModel = viewModel
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
                                Text("\(members.count) people inside")
                                Text("Cover Charge: ⬢ \(chat.coverAmount.truncatedKinValue) Kin")
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
                    .padding(20)
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        CodeButton(
                            state: viewModel.buttonState,
                            style: .filled,
                            title: "Join Room \(chat.roomNumber.roomString)"
                        ) {
                            Task {
                                try await viewModel.attemptJoinChat(
                                    chatID: chat.id,
                                    hostID: chat.ownerUser,
                                    amount: chat.coverAmount
                                )
                            }
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
                            try await viewModel.joinChat(
                                chatID: chat.id,
                                hostID: chat.ownerUser,
                                amount: chat.coverAmount
                            )
                        },
                        dismissAction: { viewModel.completeJoiningChat(chatID: chat.id) },
                        cancelAction: { viewModel.cancelJoinChatPayment() }
                    )
                }
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
            unreadCount: 0
        ),
        members: [],
        host: .init(displayName: "Bob", avatarURL: nil),
        viewModel: .mock
    )
}
