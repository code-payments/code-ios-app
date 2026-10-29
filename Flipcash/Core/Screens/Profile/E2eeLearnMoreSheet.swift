//
//  E2eeLearnMoreSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI

/// Which chat an encryption notice speaks for: a DM or a private group, which are end-to-end
/// encrypted, or a public group, which is not.
enum E2eeNoticeKind {
    case dm
    case group
    case privateGroup
}

/// What end-to-end encryption does and doesn't cover in a chat, opened from the profile footer's
/// Learn More (nodes 10416:1533 and 10557:1412).
struct E2eeLearnMoreSheet: View {

    let kind: E2eeNoticeKind

    @Binding var isPresented: Bool

    var body: some View {
        Tray(title: title, message: message, icon: icon, actions: actions) {
            VStack(spacing: 12) {
                section("ENCRYPTED", items: encrypted, isEncrypted: true)
                section("NOT ENCRYPTED", items: notEncrypted, isEncrypted: false)
            }
        }
        .accessibilityIdentifier("e2ee-learn-more-\(kind)")
    }

    /// The lock: Central's for an encrypted chat, the SF open lock for a public group, which
    /// Central lacks.
    private var icon: TrayIcon {
        switch kind {
        case .dm, .privateGroup: .central(.lock)
        case .group: .image(Image(systemName: "lock.open"))
        }
    }

    private var actions: [TrayAction] {
        [TrayAction("Got It") { isPresented = false }]
    }

    private func section(_ heading: String, items: [String], isEncrypted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.44)
                .foregroundStyle(Color.white.opacity(0.45))

            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    bullet(isEncrypted: isEncrypted)
                    Text(item)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func bullet(isEncrypted: Bool) -> some View {
        Image.icon(isEncrypted ? .circleCheck : .circleMinus)
            .iconSize(18)
            .foregroundStyle(isEncrypted ? Color.success : Color.white.opacity(0.5))
            // Sits the glyph on the text's first baseline.
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
    }

    private var title: String {
        switch kind {
        case .dm, .privateGroup: "Your Messages Are Private"
        case .group:             "Public Groups Are Not Encrypted"
        }
    }

    private var message: String {
        switch kind {
        case .dm:
            "Messages and media in this chat are end-to-end encrypted. Only you and the person you\u{2019}re chatting with can read them."
        case .group:
            "End-to-end encryption covers chats between two people. Messages in public groups are stored on Flipcash servers in plain text."
        case .privateGroup:
            "Messages and media in this group are end-to-end encrypted. Only its members can read them, and the host approves everyone who joins."
        }
    }

    private var encrypted: [String] {
        switch kind {
        case .dm, .privateGroup: ["All message text", "All media"]
        case .group:             ["Messages and media in 1:1 chats"]
        }
    }

    private var notEncrypted: [String] {
        switch kind {
        case .dm:
            [
                "Payments, which are recorded on the Solana blockchain",
                "Reactions, and who sent them",
                "Public group chats",
                "Messages sent before encryption became available",
            ]
        case .group:
            [
                "Public group chats, including this one",
                "Payments, which are recorded on the Solana blockchain",
            ]
        case .privateGroup:
            [
                "The group\u{2019}s name, photo, description and cover",
                "Who is in the group, and how many",
                "Payments, which are recorded on the Solana blockchain",
                "Reactions, and who sent them",
            ]
        }
    }
}

/// The encryption notice pinned under a chat's profile (nodes 10557:1304 and 10557:1643): a lock
/// and one line, with Learn More opening ``E2eeLearnMoreSheet``.
/// Figma's Central lock for an encrypted chat; the SF open lock for a public group, which Central lacks.
private struct E2eeLockGlyph: View {
    let kind: E2eeNoticeKind
    let size: CGFloat

    var body: some View {
        switch kind {
        case .dm, .privateGroup:
            Image.icon(.lock).iconSize(size * 1.2)
        case .group:
            Image(systemName: "lock.open.fill").font(.system(size: size, weight: .semibold))
        }
    }
}

struct E2eeFooter: View {

    let kind: E2eeNoticeKind

    @State private var isShowingSheet = false

    var body: some View {
        Button {
            isShowingSheet = true
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    E2eeLockGlyph(kind: kind, size: 14)
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text(kind == .group ? "Public groups are not end-to-end encrypted" : "Messages are end-to-end encrypted")
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
        .tray(isPresented: $isShowingSheet) {
            E2eeLearnMoreSheet(kind: kind, isPresented: $isShowingSheet)
        }
    }
}
