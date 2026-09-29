//
//  E2eeLearnMoreSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashUI

/// Which chat an encryption notice speaks for: a DM, which is end-to-end encrypted, or a group,
/// which is not.
enum E2eeNoticeKind {
    case dm
    case group
}

/// What end-to-end encryption does and doesn't cover in a chat, opened from the profile footer's
/// Learn More (nodes 10416:1533 and 10557:1412).
struct E2eeLearnMoreSheet: View {

    let kind: E2eeNoticeKind

    @Binding var isPresented: Bool

    var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    CloseButton(style: .glass, binding: $isPresented)
                }

                Image(systemName: lockSymbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 70, height: 70)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .padding(.top, 8)

                Text(title)
                    .font(.appTextXL)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                // `fixedSize` for the reason ``MuteChatSheet`` gives: `PartialSheet` proposes the
                // full screen height first, and a short proposal would otherwise truncate the text.
                Text(message)
                    .font(.default(size: 15, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                VStack(spacing: 16) {
                    section("ENCRYPTED", items: encrypted, isEncrypted: true)
                    section("NOT ENCRYPTED", items: notEncrypted, isEncrypted: false)
                }
                .padding(.top, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, bottomPadding)
        }
        .accessibilityIdentifier("e2ee-learn-more-\(kind)")
    }

    private func section(_ heading: String, items: [String], isEncrypted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.default(size: 11, weight: .bold))
                .tracking(0.44)
                .foregroundStyle(Color.white.opacity(0.45))

            ForEach(items, id: \.self) { item in
                HStack(spacing: 12) {
                    bullet(isEncrypted: isEncrypted)
                    Text(item)
                        .font(.default(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func bullet(isEncrypted: Bool) -> some View {
        Group {
            if isEncrypted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.backgroundMain, Color(r: 47, g: 194, b: 107))
            } else {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.white.opacity(0.7), Color.white.opacity(0.12))
            }
        }
        .symbolRenderingMode(.palette)
        .font(.system(size: 18, weight: .semibold))
        .frame(width: 18, height: 18)
    }

    private var lockSymbol: String {
        switch kind {
        case .dm:    "lock.fill"
        case .group: "lock.open.fill"
        }
    }

    private var title: String {
        switch kind {
        case .dm:    "Your messages are private"
        case .group: "Group chats aren\u{2019}t encrypted"
        }
    }

    private var message: String {
        switch kind {
        case .dm:
            "Messages and photos in this chat are end-to-end encrypted. Only you and the person you\u{2019}re chatting with can read them. Not even Flipcash can."
        case .group:
            "End-to-end encryption covers chats between two people. Messages in group chats are stored on Flipcash servers in a form Flipcash can read."
        }
    }

    private var encrypted: [String] {
        switch kind {
        case .dm:    ["Text messages and replies", "Photos you send"]
        case .group: ["Messages in DMs"]
        }
    }

    private var notEncrypted: [String] {
        switch kind {
        case .dm:
            [
                "Tips and payments, which are recorded on Solana",
                "Reactions, and who sent them",
                "That a message was edited or deleted",
                "Group chats",
                "Messages sent before encryption was turned on",
            ]
        case .group:
            [
                "Group chats, including this one",
                "Tips and payments, which are recorded on Solana",
            ]
        }
    }

    /// The design's 16 under the last section, less what the sheet already holds back for the home
    /// indicator.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
    }
}

/// The encryption notice pinned under a chat's profile (nodes 10557:1304 and 10557:1643): a lock
/// and one line, with Learn More opening ``E2eeLearnMoreSheet``.
struct E2eeFooter: View {

    let kind: E2eeNoticeKind

    @State private var isShowingSheet = false

    var body: some View {
        Button {
            isShowingSheet = true
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: kind == .dm ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text(kind == .dm ? "Messages are end-to-end encrypted" : "Group chats aren't end-to-end encrypted")
                        .font(.default(size: 13, weight: .medium))
                        .foregroundStyle(Color(r: 143, g: 143, b: 148))
                }
                Text("Learn More")
                    .font(.default(size: 13, weight: .bold))
                    .foregroundStyle(Color.textMain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("e2ee-footer-\(kind)")
        .sheet(isPresented: $isShowingSheet) {
            E2eeLearnMoreSheet(kind: kind, isPresented: $isShowingSheet)
        }
    }
}
