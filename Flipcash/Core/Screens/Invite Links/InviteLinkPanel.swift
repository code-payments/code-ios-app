//
//  InviteLinkPanel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The invite sheet's link block for a host (frames 1a, 1b, nodes 12844:60 and 12844:110): the
/// current link in a pill, its actions, the meta line and the footnote.
///
/// Plain state in, closures out, so every frame renders in a preview without a session.
struct InviteLinkPanel: View {

    enum Pill: Equatable {
        /// The invites haven't loaded yet.
        case loading
        /// No active link of the viewer's: the first Share or Copy makes one.
        case none
        /// `CreateInvite` is in flight.
        case creating
        case link(URL)
    }

    let pill: Pill
    /// "Expires Nov 3 · 0 joined" under a current link; the new link's terms otherwise.
    let meta: String
    let didCopy: Bool
    let onShare: () -> Void
    let onCopy: () -> Void
    let onShareRequestLink: () -> Void
    let onManage: () -> Void
    /// Show Group Card, which carries the plain group link (Decision 6). Nil hides the row.
    let onShowGroupCard: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(InviteLinkCopy.sheetSubtitle)
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 16)

            pillView
                .padding(.bottom, 8)

            row("Share Link", systemImage: "paperplane", identifier: "invite-link-share", action: onShare)
            separator
            row(didCopy ? "Copied" : "Copy Invite Link", systemImage: didCopy ? "checkmark.circle" : "link", identifier: "invite-link-copy", action: onCopy)
            separator
            row("Share Request-to-Join Link", systemImage: "link", identifier: "invite-link-request", action: onShareRequestLink)
            separator
            row("Manage Invites", systemImage: "line.3.horizontal", identifier: "invite-link-manage", action: onManage)
            if let onShowGroupCard {
                separator
                row("Show Group Card", systemImage: "qrcode", identifier: "group-card-tile", action: onShowGroupCard)
            }

            Text(meta)
                .font(.appTextCaption)
                .foregroundStyle(Color.textMain.opacity(0.5))
                .padding(.top, 16)
            Text(InviteLinkCopy.footnote)
                .font(.appTextCaption)
                .foregroundStyle(Color.textMain.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var pillView: some View {
        HStack(spacing: 8) {
            switch pill {
            case .loading:
                ProgressView().tint(Color.textMain)
            case .creating:
                ProgressView().tint(Color.textMain)
                Text(InviteLinkCopy.creating)
                    .foregroundStyle(Color.textMain.opacity(0.5))
            case .none:
                Text(Self.placeholder)
                    .foregroundStyle(Color.textMain.opacity(0.5))
            case .link(let url):
                // Elided in the middle, so the host and the secret's tail both show.
                Text(Self.display(url))
                    .foregroundStyle(Color.textMain)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .font(.appTextMedium)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("invite-link-pill")
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.rowSeparator)
            .frame(height: 1)
            .padding(.leading, 46)
    }

    private func row(_ title: String, systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: systemImage)
                    .frame(width: 26)
                Text(title)
                    .font(.appTextMedium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain.opacity(0.5))
            }
            .foregroundStyle(Color.textMain)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// The link without its scheme, as the pill draws it.
    static func display(_ url: URL) -> String {
        let string = url.absoluteString
        guard let range = string.range(of: "://") else { return string }
        return String(string[range.upperBound...])
    }

    /// What the pill holds before a link exists: the link's shape, with no secret.
    static let placeholder = "app.flipcash.com/chat/invite"
}

// MARK: - Previews -

private let previewURL = URL(string: "https://app.flipcash.com/chat/invite#s=kQ3vR8mZp4LwN2yTb7cXe1aFhJ6sDg0uVq5oIrKxT9a")!

private func panel(_ pill: InviteLinkPanel.Pill, meta: String) -> some View {
    Background(color: .backgroundMain) {
        InviteLinkPanel(
            pill: pill,
            meta: meta,
            didCopy: false,
            onShare: {},
            onCopy: {},
            onShareRequestLink: {},
            onManage: {},
            onShowGroupCard: {}
        )
        .padding(20)
    }
}

#Preview("1a · Current link") {
    panel(.link(previewURL), meta: "Expires Nov 3 · 0 joined")
}

#Preview("1b · Creating link") {
    panel(.creating, meta: InviteLinkCopy.defaultExpiry)
}

#Preview("No link yet") {
    panel(.none, meta: InviteLinkCopy.defaultExpiry)
}
