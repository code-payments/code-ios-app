//
//  BlockedUsersScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Lists the users the owner has blocked, with an unblock confirmation per row.
struct BlockedUsersScreen: View {

    @Environment(BlocklistController.self) private var blocklistController
    @Environment(Session.self) private var session
    @State private var dialogItem: DialogItem?
    @State private var hasLoaded = false

    private let insets = EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            Group {
                if blocklistController.blockedUsers.isEmpty && hasLoaded {
                    VStack(spacing: 8) {
                        Text("No One Blocked")
                            .font(.appTextMedium)
                            .foregroundStyle(.textMain)
                        Text("Block people from sending you messages by tapping their profile and selecting block")
                            .font(.appTextSmall)
                            .foregroundStyle(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                } else if !blocklistController.blockedUsers.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(blocklistController.blockedUsers) { user in
                                blockedRow(user)
                            }
                        }
                        .font(.appDisplayXS)
                        .padding(.horizontal, 20)
                    }
                    .softScrollEdge(for: .top)
                }
            }
        }
        .navigationTitle("Blocked")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
        .task { await blocklistController.refresh(); hasLoaded = true }
    }

    private func blockedRow(_ user: BlockedUserProfile) -> some View {
        // Always blurred (imageData nil) — the Blocked list shows the blurred photo.
        Row(insets: insets, accessory: .chevron) {
            ContactAvatarView(
                id: user.userID.uuidString,
                displayName: user.displayName,
                imageData: nil,
                blurhash: user.avatarBlurhash,
                size: 44
            )
            Text(user.displayName)
                .foregroundStyle(.textMain)
        } action: {
            dialogItem = unblockDialog(user)
        }
    }

    private func unblockDialog(_ user: BlockedUserProfile) -> DialogItem {
        .info(
            title: "Unblock \(user.displayName)?",
            subtitle: "The conversation with them will reappear in Tips"
        ) {
            DialogAction.standard("Unblock") {
                Task {
                    do {
                        try await blocklistController.unblock(userID: user.userID)
                    } catch {
                        session.dialogItem = .error(title: "Something Went Wrong", subtitle: "We were unable to unblock the user. Please try again")
                        ErrorReporting.captureError(error, reason: "Failed to unblock user")
                    }
                }
            }
            DialogAction.cancel()
        }
    }
}
