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
    
    @State private var selectedProfile: MemberGrid.Member?
    
    private let userID: UserID
    private let chatID: ChatID
    private let state: AuthenticatedState
    private let container: AppContainer
    
    var room: RoomDescription? {
        updateableRoom.value
    }
    
    var gridMembers: [MemberGrid.Member] {
        let userID = userID.uuid
        return updateableMembers.value.map {
            .init(
                id: $0.serverID,
                isSelf: $0.serverID == userID,
                isSpeaker: $0.canSend,
                isModerator: $0.canModerate,
                verificationType: $0.profile?.verificationType ?? .none,
                name: $0.resolvedDisplayName,
                avatarURL: $0.profile?.avatar?.original
            )
        }
    }
    
    // MARK: - Init -
    
    init(userID: UserID, chatID: ChatID, state: AuthenticatedState, container: AppContainer) {
        self.userID = userID
        self.chatID = chatID
        self.state = state
        self.container = container
        self.viewModel = state.chatViewModel
        let chatController = state.chatController
        
        let updateableRoom = Updateable {
            try? chatController.getRoom(chatID: chatID)
        }
        
        let updateableMembers = Updateable {
            (try? chatController.getMembers(roomID: chatID)) ?? []
        }
        
        self._updateableRoom    = .init(wrappedValue: updateableRoom)
        self._updateableMembers = .init(wrappedValue: updateableMembers)
        
        self.chatController = chatController
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                if let room {
                    let isSelfHost = room.room.ownerUserID == userID.uuid
                    MemberGrid(
                        chatName: room.room.formattedTitle,
                        avatarData: room.room.serverID.data,
                        members: gridMembers,
                        shareRoomNumber: room.room.roomNumber,
                        isClosed: !room.room.isOpen,
                        canEdit: isSelfHost,
                        longPressEnabled: isSelfHost,
                        longPressAction: longPressAction,
                        avatarAction: avatarAction,
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
                    Action.standard(systemImage: "hexagon", title: "Change Listener Message Fee") {
                        viewModel.showChangeCover()
                    }
                
//                    Action.standard(systemImage: "character.cursor.ibeam", title: "Change Flipchat Name") {
//                        viewModel.showChangeRoomName(existingName: room?.room.title)
//                    }
                
                    Action.standard(systemImage: "powersleep", title: room.isOpen ? "Close Flipchat Temporarily" : "Open Flipchat") {
                        viewModel.setRoomStatus(chatID: ChatID(uuid: room.serverID), open: !room.isOpen)
                    }
                }
                
                Action.standard(systemImage: "rectangle.portrait.and.arrow.right", title: "Leave Flipchat") {
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
            .sheet(item: $selectedProfile) { member in
                let memberID = UserID(uuid: member.id)
                ProfileScreen(
                    userID: memberID,
                    isSelf: self.userID == memberID,
                    state: state,
                    container: container
                )
            }
        }
    }
    
    // MARK: - Actions -
    
    private func avatarAction(member: MemberGrid.Member) {
        selectedProfile = member
    }
    
    private func longPressAction(member: MemberGrid.Member) {
        let isHost = room?.room.ownerUserID == userID.uuid
        guard isHost else {
            return
        }
        
        let name = member.name ?? ""
        let userID = UserID(uuid: member.id)
        
        if member.isSpeaker {
            banners.show(
                style: .notification,
                title: "Remove \(name) as a Speaker?",
                description: "They will no longer be able to message for free",
                position: .bottom,
                actions: [
                    .standard(title: "Remove as Speaker") {
                        Task {
                            try await chatController.demoteUser(userID: userID, chatID: chatID)
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
        } else {
            banners.show(
                style: .notification,
                title: "Make \(name) a Speaker?",
                description: "They will be able to message for free",
                position: .bottom,
                actions: [
                    .standard(title: "Make a Speaker") {
                        Task {
                            try await chatController.promoteUser(userID: userID, chatID: chatID)
                        }
                    },
                    .cancel(title: "Cancel"),
                ]
            )
        }
    }
}

#Preview {
    RoomDetailsScreen(
        userID: .mock,
        chatID: .mock,
        state: .mock,
        container: .mock
    )
}
