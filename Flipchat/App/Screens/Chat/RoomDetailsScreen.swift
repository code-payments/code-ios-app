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
        
        room = try chatController.getRoom(chatID: chatID)
    }
    
    func reload() throws {
        room = try chatController.getRoom(chatID: chatID)
    }
}

struct RoomDetailsScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel
    @ObservedObject private var chatController: ChatController
    
    @State private var detailsState: RoomDetailsState
    
    private let chatID: ChatID
    
    var room: RoomDescription? {
        detailsState.room
    }
    
    // MARK: - Init -
    
    init(chatID: ChatID, viewModel: ChatViewModel, chatController: ChatController) {
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
                        RoomCard(
                            title: room.room.formattedTitle,
                            host: room.hostDisplayName,
                            memberCount: room.memberCount,
                            cover: room.room.cover,
                            avatarData: room.room.serverID.data
                        )
                    
                        Spacer()
                    
                        VStack(spacing: 10) {
                            // Only show for room hosts
                            if viewModel.userID.uuid == room.room.ownerUserID {
                                CodeButton(
                                    style: .filled,
                                    title: "Customize"
                                ) {
                                    viewModel.showCustomizeRoomModal()
                                }
                            }
                            
                            CodeButton(
                                state: viewModel.buttonStateLeaveChat,
                                style: .subtle,
                                title: "Leave Room \(room.room.roomNumber.formattedRoomNumberShort)"
                            ) {
                                Task {
                                    viewModel.attemptLeaveChat(
                                        chatID: chatID,
                                        roomNumber: room.room.roomNumber
                                    )
                                }
                            }
                        }
                    }
                    .padding([.top, .leading, .trailing], 20)
                    .transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea(.keyboard)
            .animation(.easeInOut, value: room == nil)
            .foregroundColor(.textMain)
            .toolbar {
                if let room {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            ShareSheet.present(url: .flipchatRoom(roomNumber: room.room.roomNumber, messageID: nil))
                        } label: {
                            Image.asset(.send)
                                .padding(.leading, 15)
                                .padding(.trailing, 8)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.isShowingCustomize) {
                PartialSheet {
                    ModalButtons(
                        isPresented: $viewModel.isShowingCustomize,
                        actions: [
                            .init(title: "Change Room Name") {
                                viewModel.showChangeRoomName(existingName: detailsState.room?.room.title)
                            },
                            .init(title: "Change Cover Charge") {
                                viewModel.showChangeCover()
                            },
                        ]
                    )
                }
            }
            .sheet(isPresented: $viewModel.isShowingChangeCover) {
                ChangeCoverScreen(
                    chatID: chatID,
                    viewModel: viewModel
                )
            }
            .sheet(isPresented: $viewModel.isShowingChangeRoomName) {
                ChangeRoomNameScreen(
                    chatID: chatID,
                    viewModel: viewModel
                )
            }
            .onChange(of: chatController.chatsDidChange) { _, _ in
                try? detailsState.reload()
            }
        }
    }
    
    private func onAppear() {
        
    }
}

#Preview {
    RoomDetailsScreen(
        chatID: .mock,
        viewModel: .mock,
        chatController: .mock
    )
}
