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
    
    @State private var showingPaymentConfirmation: Bool = false
    
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
                                Text("ID: \(chat.serverID.hexString().prefix(16))")
                                Text("Cover Charge: ⬢ \(chat.coverCharge) Kin")
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
                    .padding(20)
                    
                    Spacer()
                    
                    CodeButton(
                        state: viewModel.buttonState,
                        style: .filled,
                        title: kind.titleFor(roomNumber: chat.roomNumber)
                    ) {
                        switch kind {
                        case .joinRoom:
                            viewModel.attemptJoinChat(
                                chatID: chatID,
                                hostID: UserID(data: chat.ownerUserID)
                            )
                        case .leaveRoom:
                            viewModel.attemptLeaveChat(
                                chatID: chatID,
                                roomNumber: chat.roomNumber
                            )
                        }
                    }
                }
                .padding(20)
            }
            .foregroundColor(.textMain)
            .sheet(isPresented: $showingPaymentConfirmation) {
                PartialSheet {
                    ModalPaymentConfirmation(
                        amount: KinAmount(kin: 100, rate: .oneToOne).kin.formattedFiat(rate: .oneToOne, suffix: nil),
                        currency: .kin,
                        primaryAction: "Swipe to Pay",
                        secondaryAction: "Cancel",
                        paymentAction: {
                            viewModel.joinChat(
                                chatID: ChatID(data: chat.serverID),
                                hostID: UserID(data: chat.ownerUserID)
                            )
                        },
                        dismissAction: { showingPaymentConfirmation = false },
                        cancelAction: { showingPaymentConfirmation = false }
                    )
                }
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

private struct AspectRatioCard<Content>: View where Content: View {
    
    private let padding: CGFloat = 20
    private let ratio: CGFloat = 1.647
    
    public let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = size(for: geometry)
            
            content()
                .frame(width: size.width, height: size.height)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.25), radius: 40)
                .position(position(for: geometry, size: size))
        }
    }

    private func size(for geometry: GeometryProxy) -> CGSize {
        var h = geometry.size.height - padding * 2
        var w = h / ratio
        
        if w + padding * 2 > geometry.size.width {
            w = geometry.size.width - padding * 2
            h = w * ratio
        }
        
        return .init(
            width: max(w, 0),
            height: max(h, 0)
        )
    }
    
    private func position(for geometry: GeometryProxy, size: CGSize) -> CGPoint {
        let y = (geometry.size.height - size.height) * 0.5 + size.height * 0.5
        let x = (geometry.size.width  - size.width)  * 0.5 + size.width  * 0.5
        
        return .init(x: x, y: y)
    }
}

#Preview {
    RoomDetailsScreen(
        kind: .joinRoom,
        chatID: .mock,
        viewModel: .mock
    )
}
