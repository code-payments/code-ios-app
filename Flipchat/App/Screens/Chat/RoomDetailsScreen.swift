//
//  RoomDetailsScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct RoomDetailsScreen: View {
    
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: ChatViewModel
    @ObservedObject private var chatController: ChatController
    
    @StateObject private var updateableRoom: Updateable<RoomDescription?>
    @StateObject private var updateableMembers: Updateable<[MemberRow]>
    
    private let userID: UserID
    private let chatID: ChatID
    
    var room: RoomDescription? {
        updateableRoom.value
    }
    
    var gridMembers: [MemberGrid.Member] {
        updateableMembers.value.map {
            .init(
                id: $0.serverID,
                isSpeaker: $0.canSend,
                name: $0.displayName
            )
        }
    }
    
    // MARK: - Init -
    
    init(userID: UserID, chatID: ChatID, viewModel: ChatViewModel, chatController: ChatController) {
        self.userID = userID
        self.chatID = chatID
        self.viewModel = viewModel
        self.chatController = chatController
        
        let updateableRoom = Updateable {
            try? chatController.getRoom(chatID: chatID)
        }
        
        let updateableMembers = Updateable {
            (try? chatController.getMembers(roomID: chatID)) ?? []
        }
        
        self._updateableRoom    = .init(wrappedValue: updateableRoom)
        self._updateableMembers = .init(wrappedValue: updateableMembers)
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                if let room {
                    MemberGrid(
                        chatName: room.room.formattedTitle,
                        avatarData: room.room.serverID.data,
                        members: gridMembers,
                        shareRoomNumber: room.room.roomNumber,
                        isClosed: !room.room.isOpen,
                        canEdit: room.room.ownerUserID == userID.uuid,
                        editAction: {
                            viewModel.showChangeRoomName(existingName: room.room.title)
                        }
                    )
                }
            }
            .ignoresSafeArea(.keyboard)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showCustomizeRoomModal()
                    } label: {
                        Image(systemName: "gearshape")
                            .padding(10)
                    }
                }
            }
            .buttonSheet(isPresented: $viewModel.isShowingCustomize) {
                // Show for hosts only
                let isHost = room?.room.ownerUserID == userID.uuid
                if isHost, let room = room?.room {
                    Action.standard(systemImage: "hexagon", title: "Change Cover Charge") {
                        viewModel.showChangeCover()
                    }
                
//                    Action.standard(systemImage: "character.cursor.ibeam", title: "Change Flipchat Name") {
//                        viewModel.showChangeRoomName(existingName: room?.room.title)
//                    }
                
                    Action.standard(systemImage: "powersleep", title: room.isOpen ? "Close Flipchat Temporarily" : "Open Flipchat") {
                        viewModel.setRoomStatus(chatID: ChatID(uuid: room.serverID), open: !room.isOpen)
                    }
                }
                
                Action.destructive(systemImage: "rectangle.portrait.and.arrow.right", title: "Leave Flipchat") {
                    guard let room else {
                        return
                    }
                    
                    Task {
                        viewModel.attemptLeaveChat(
                            chatID: chatID,
                            roomNumber: room.room.roomNumber
                        )
                    }
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
        }
    }
}

#Preview {
    RoomDetailsScreen(
        userID: .mock,
        chatID: .mock,
        viewModel: .mock,
        chatController: .mock
    )
}
