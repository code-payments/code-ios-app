//
//  InviteLinkActionSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// Frame 2b (node 12886:56): what a Manage Invites row offers. Drawn like ``MuteChatSheet``, the
/// same on both platforms: the link's own readout, then Share Link and a red Revoke Link.
///
/// Share Link is only for a link this device holds the secret for; a link made elsewhere can still
/// be revoked.
struct InviteLinkActionSheet: View {

    let entry: GroupInviteLinks.Entry
    @Binding var isPresented: Bool
    let onShare: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    header
                    Text(meta)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                VStack(spacing: 12) {
                    if entry.url != nil {
                        ChatActionRow(
                            icon: Image(systemName: "paperplane"),
                            title: "Share Link",
                            accessibilityIdentifier: "invite-link-share"
                        ) {
                            onShare()
                            isPresented = false
                        }
                    }
                    ChatActionRow(
                        icon: Image(systemName: "nosign"),
                        title: "Revoke Link",
                        tint: .textError,
                        accessibilityIdentifier: "invite-link-revoke"
                    ) {
                        onRevoke()
                        isPresented = false
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, bottomPadding)
        }
    }

    /// Mirrors ``MuteChatSheet``'s title bar.
    private var header: some View {
        ZStack {
            Text("Invite Link")
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
            HStack {
                Spacer()
                CloseButton(style: .glass, binding: $isPresented)
            }
        }
    }

    /// "Created Oct 27 · 0 joined · Expires Nov 3".
    private var meta: String {
        let detail = InviteLinkCopy.rowDetail(entry)
        return InviteLinkCopy.created(entry.invite).map { "\($0) · \(detail)" } ?? detail
    }

    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
    }
}
