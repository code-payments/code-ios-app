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

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer

    /// How long the copy row stays on its checkmark before reverting — the beat the tip-card link
    /// row holds.
    private static let confirmationDuration: Duration = .seconds(1.5)

    @State private var didCopy = false

    private var url: URL {
        .groupChatInvite(for: conversationID)
    }

    /// The group's own title, which names it in the shared message.
    ///
    /// Read from the record rather than through `displayName(for:)`: that resolves an untitled chat
    /// to a counterpart's name or to "Flipcash User", and a group invited to under either of those
    /// would be worse than one invited to with no name at all. Nil shares the bare link — see
    /// ``GroupInviteShareItem``.
    private var title: String? {
        conversation?.title
    }

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    /// The group's picture for the share sheet's own preview card.
    ///
    /// Decoded at the tap rather than in a computed property, so a thumbnail isn't re-decoded on
    /// every render of a sheet that shows it nowhere. Nil while the avatar hasn't loaded or the
    /// group has none — the card then carries the name alone.
    private func icon() -> UIImage? {
        sessionContainer.profileAvatars
            .data(for: .chat(conversationID))
            .flatMap(UIImage.init(data:))
    }

    var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(spacing: 20) {
                header

                VStack(spacing: 12) {
                    ChatActionRow(
                        icon: .asset(.at),
                        title: "Send Invite Link",
                        accessibilityIdentifier: "group-invite-send"
                    ) {
                        ShareSheet.present(
                            activityItem: GroupInviteShareItem(url: url, title: title, icon: icon())
                        ) { _ in }
                    }

                    ChatActionRow(
                        icon: didCopy ? .system(.circleCheck) : .asset(.squareBehindSquare),
                        title: didCopy ? "Copied" : "Copy Invite Link",
                        accessibilityIdentifier: "group-invite-copy",
                        action: copy
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, bottomPadding)
        }
        .task {
            // Idempotent: the store returns without a round trip once the bytes are in memory or
            // on disk. Loading here rather than relying on the presenting screen keeps the preview
            // card's icon independent of which screen opened the sheet.
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
        }
    }

    /// The sheet's own title bar. ``PartialSheet`` takes its height from the content it wraps, so
    /// there is no navigation bar to hang the title and close button on — and a `NavigationStack`
    /// here would report a full-screen height and defeat the wrap.
    private var header: some View {
        ZStack {
            Text("Invite to Join Group")
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)

            HStack {
                Spacer()
                CloseButton(binding: $isPresented)
                    .foregroundStyle(Color.textMain)
            }
        }
    }

    /// The design's 16 under the last row, less whatever the sheet already holds back for the home
    /// indicator — stacking the two would triple the design's gap.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
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
