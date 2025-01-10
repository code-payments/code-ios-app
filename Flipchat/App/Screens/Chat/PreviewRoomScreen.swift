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
                    RoomCard(
                        title: chat.formattedTitle,
                        host: host.displayName,
                        memberCount: members.count,
                        cover: chat.coverAmount,
                        avatarData: chat.id.data
                    )
                    .padding(.bottom, 20)
                    
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
            canMute: false
        ),
        members: [],
        host: .init(displayName: "Bob", avatarURL: nil),
        viewModel: .mock,
        isModal: false
    )
}
