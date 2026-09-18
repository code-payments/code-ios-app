//
//  NewChatScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// What the `+` in the Chats bar opens: the two kinds of chat a user can start (node
/// 10127:117987).
struct NewChatScreen: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 12) {
                ChatActionRow(
                    icon: .asset(.group),
                    title: "Create a Public Group",
                    accessibilityIdentifier: "new-chat-public-group"
                ) {
                    router.push(.newPublicGroup)
                }

                ChatActionRow(
                    icon: .asset(.at),
                    title: "Find by Username",
                    accessibilityIdentifier: "new-chat-find-by-username"
                ) {
                    router.push(.usernameLookup)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
