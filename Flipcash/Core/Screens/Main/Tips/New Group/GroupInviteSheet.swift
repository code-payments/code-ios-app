//
//  GroupInviteSheet.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// The two ways to hand out a group's invite link (node 10127:118315).
///
/// A group is not discoverable — the link built from its id is the only way in — so this is the
/// whole of its invite story, and both rows share one URL rather than each building its own.
struct GroupInviteSheet: View {

    let conversationID: ConversationID

    @Binding var isPresented: Bool

    /// How long the copy row stays on its checkmark before reverting — the beat the tip-card link
    /// row holds.
    private static let confirmationDuration: Duration = .seconds(1.5)

    @State private var didCopy = false

    private var url: URL {
        .groupChatInvite(for: conversationID)
    }

    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(spacing: 12) {
                    ChatActionRow(
                        icon: .asset(.at),
                        title: "Send Invite Link",
                        accessibilityIdentifier: "group-invite-send"
                    ) {
                        ShareSheet.present(activityItems: [url]) { _ in }
                    }

                    ChatActionRow(
                        icon: didCopy ? .system(.circleCheck) : .asset(.squareBehindSquare),
                        title: didCopy ? "Copied" : "Copy Invite Link",
                        accessibilityIdentifier: "group-invite-copy",
                        action: copy
                    )

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationTitle("Invite to Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(binding: $isPresented)
                }
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = url.absoluteString
        withAnimation(.easeInOut(duration: 0.15)) {
            didCopy = true
        }
        Task {
            try? await Task.sleep(for: Self.confirmationDuration)
            withAnimation(.easeInOut(duration: 0.15)) {
                didCopy = false
            }
        }
    }
}
