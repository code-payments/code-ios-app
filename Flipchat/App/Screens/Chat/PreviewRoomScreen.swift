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
    
    private let gridMembers: [MemberGrid.Member]
    
    // MARK: - Init -
    
    init(chat: Chat.Metadata, members: [Chat.Member], host: Chat.Identity, viewModel: ChatViewModel, isModal: Bool) {
        self.chat        = chat
        self.members     = members
        self.host        = host
        self.viewModel   = viewModel
        self.isModal     = isModal
        self.gridMembers = members.map { .init(
            id: $0.id.uuid,
            isSelf: $0.isSelf,
            isSpeaker: $0.hasSendPermission,
            isModerator: $0.hasModeratorPermission,
            name: $0.identity.displayName)
        }
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                MemberGrid(
                    chatName: chat.formattedTitle,
                    avatarData: chat.id.data,
                    members: gridMembers,
                    canEdit: false,
                    editAction: nil
                )
                                
                Spacer()
                
                VStack {
                    CodeButton(
                        state: viewModel.buttonStateWatchChat,
                        style: .filled,
                        title: "Start Listening"
                    ) {
                        Task {
                            try await viewModel.watchChat(chatID: chat.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 5)
            }
        }
        .if(isModal) { $0
            .wrapInNavigation {
                viewModel.dismissPreviewChatModal()
            }
        }
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
            canMute: false,
            isOpen: true
        ),
        members: [],
        host: .init(displayName: "Bob", avatarURL: nil),
        viewModel: .mock,
        isModal: false
    )
}
