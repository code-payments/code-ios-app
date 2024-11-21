//
//  RoomDetailsScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import SwiftData
import CodeUI
import FlipchatServices

struct RoomDetailsScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel
    
    @Query private var chats: [pChat]
    
    private var chat: pChat {
        chats[0]
    }
    
    private var members: [pMember] {
        chat.members
    }
    
    private var host: pMember? {
        members.first { chat.ownerUserID == $0.serverID }
    }
    
    private let kind: Kind
    private let chatID: ChatID
    
    // MARK: - Init -
    
    init(kind: Kind, chatID: ChatID, viewModel: ChatViewModel) {
        self.kind = kind
        self.chatID = chatID
        self.viewModel = viewModel
        _chats = Query(filter: #Predicate { $0.serverID == chatID.data })
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
                                if let host {
                                    Text("Hosted by \(host.displayName)")
                                }
                                Text("\(members.count) people inside")
                                Text("Cover Charge: ⬢ \(chat.coverCharge.truncatedKinValue) Kin")
                            }
                            .opacity(0.8)
                            .font(.appTextSmall)
                            Spacer()
                        }
                        .shadow(color: Color.black.opacity(0.2), radius: 1, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            DeterministicGradient(data: chat.serverID)
                        }
                    }
                    .padding(50)
                    
                    Spacer()
                    
                    VStack(spacing: 20) {
                        // Only show for room hosts
                        if let host, host.serverID == viewModel.userID.data {
                            CodeButton(
                                state: viewModel.buttonState,
                                style: .filled,
                                title: "Change Cover Charge"
                            ) {
                                viewModel.showChangeCover(currentCover: chat.coverCharge)
                            }
                        }
                        
                        CodeButton(
                            state: viewModel.buttonState,
                            style: .filled,
                            title: kind.titleFor(roomNumber: chat.roomNumber)
                        ) {
                            switch kind {
                            case .joinRoom:
                                viewModel.attemptJoinChat(
                                    chatID: chatID,
                                    hostID: UserID(data: chat.ownerUserID),
                                    amount: chat.coverCharge
                                )
                            case .leaveRoom:
                                viewModel.attemptLeaveChat(
                                    chatID: chatID,
                                    roomNumber: chat.roomNumber
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
                        amount: chat.coverCharge.formattedFiat(rate: .oneToOne, truncated: true, showOfKin: true),
                        currency: .kin,
                        primaryAction: "Swipe to Pay",
                        secondaryAction: "Cancel",
                        paymentAction: {
                            viewModel.joinChat(
                                chatID: ChatID(data: chat.serverID),
                                hostID: UserID(data: chat.ownerUserID),
                                amount: chat.coverCharge
                            )
                        },
                        dismissAction: { viewModel.isShowingJoinPayment = false },
                        cancelAction: { viewModel.isShowingJoinPayment = false }
                    )
                }
            }
            .sheet(isPresented: $viewModel.isShowingChangeCover) {
                ChangeCoverScreen(chatID: chatID, viewModel: viewModel)
            }
        }
    }
    
    private func onAppear() {
        
    }
}

extension RoomDetailsScreen {
    enum Kind {
        case joinRoom
        case leaveRoom
        
        fileprivate func titleFor(roomNumber: RoomNumber) -> String {
            switch self {
            case .joinRoom:
                return "Join Room \(roomNumber.roomString)"
            case .leaveRoom:
                return "Leave Room \(roomNumber.roomString)"
            }
        }
    }
}

#Preview {
    RoomDetailsScreen(
        kind: .joinRoom,
        chatID: .mock,
        viewModel: .mock
    )
}
