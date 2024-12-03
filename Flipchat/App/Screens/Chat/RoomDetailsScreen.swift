//
//  RoomDetailsScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import FlipchatServices

@MainActor
@Observable
private class RoomDetailsState {
    
    var room: RoomDescription?
    
    private let chatID: ChatID
    private let chatController: ChatController
    
    init(chatID: ChatID, chatController: ChatController) throws {
        self.chatID = chatID
        self.chatController = chatController
        
        room = try chatController.fetchRoom(chatID: chatID)
    }
    
    func reload() throws {
        room = try chatController.fetchRoom(chatID: chatID)
    }
}

struct RoomDetailsScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel
    @ObservedObject private var chatController: ChatController
    
    @State private var detailsState: RoomDetailsState
    
    private let kind: Kind
    private let chatID: ChatID
    
    var room: RoomDescription? {
        detailsState.room
    }
    
    // MARK: - Init -
    
    init(kind: Kind, chatID: ChatID, viewModel: ChatViewModel, chatController: ChatController) {
        self.kind = kind
        self.chatID = chatID
        self.viewModel = viewModel
        self.chatController = chatController
        self.detailsState = try! RoomDetailsState(chatID: chatID, chatController: chatController)
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            GeometryReader { geometry in
                if let room = room {
                    VStack(spacing: 0) {
                        AspectRatioCard {
                            VStack {
                                Spacer()
                                Image(with: .brandLarge)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 50)
                                Spacer()
                                Text(room.room.roomNumber.formattedRoomNumber)
                                    .font(.appDisplaySmall)
                                
                                Spacer()
                                VStack(spacing: 4) {
                                    if let host = room.hostDisplayName {
                                        Text("Hosted by \(host)")
                                    }
                                    Text("\(room.memberCount) people inside")
                                    Text("Cover Charge: ⬢ \(room.room.cover.truncatedKinValue) Kin")
                                }
                                .opacity(0.8)
                                .font(.appTextSmall)
                                Spacer()
                            }
                            .shadow(color: Color.black.opacity(0.2), radius: 1, y: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                DeterministicGradient(data: room.room.serverID.data)
                            }
                        }
                        .padding(20)
                    
                        Spacer()
                    
                        VStack(spacing: 20) {
                            // Only show for room hosts
                            if viewModel.userID.uuid == room.room.ownerUserID {
                                CodeButton(
                                    style: .filled,
                                    title: "Change Cover Charge"
                                ) {
                                    viewModel.showChangeCover(currentCover: room.room.cover)
                                }
                            }
                            
                            CodeButton(
                                state: viewModel.buttonState,
                                style: .filled,
                                title: kind.titleFor(roomNumber: RoomNumber(room.room.roomNumber))
                            ) {
                                Task {
                                    switch kind {
                                    case .joinRoom:
                                        try await viewModel.attemptJoinChat(
                                            chatID: chatID,
                                            hostID: UserID(uuid: room.room.ownerUserID),
                                            amount: room.room.cover
                                        )
                                    case .leaveRoom:
                                        viewModel.attemptLeaveChat(
                                            chatID: chatID,
                                            roomNumber: room.room.roomNumber
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut, value: room == nil)
            .foregroundColor(.textMain)
            .sheet(isPresented: $viewModel.isShowingChangeCover) {
                ChangeCoverScreen(chatID: chatID, viewModel: viewModel)
            }
            .onChange(of: chatController.chatsDidChange) { _, _ in
                try? detailsState.reload()
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
        viewModel: .mock,
        chatController: .mock
    )
}
