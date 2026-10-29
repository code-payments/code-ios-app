//
//  InviteLinkPanel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The invite share sheet's link block (surface 1, pill from frames 1a and 1b, nodes 12844:60 and
/// 12844:110): the current link with its middle elided, or "Creating link…" while the tap that
/// opened the sheet makes it, and one line describing the link once it exists.
///
/// Plain state in, so each state renders in a preview without a session.
struct InviteLinkPanel: View {

    enum Pill: Equatable {
        /// `CreateInvite`, or the load before it, is in flight.
        case creating
        case link(URL)
    }

    let pill: Pill
    /// "Expires Nov 3 · 0 joined", from the link itself. Nil until the link exists.
    let meta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pillView
            if let meta {
                Text(meta)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("invite-link-meta")
            }
        }
    }

    private var pillView: some View {
        HStack(spacing: 10) {
            switch pill {
            case .creating:
                ProgressView()
                    .tint(Color.textMain)
                    .frame(width: 18, height: 18)
                Text(InviteLinkCopy.creating)
                    .foregroundStyle(Color.textSecondary)
            case .link(let url):
                // Elided in the middle, so the host and the secret's tail both show.
                Text(Self.display(url))
                    .foregroundStyle(Color.textMain)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .font(.default(size: 14, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("invite-link-pill")
    }

    /// The link without its scheme, as the pill draws it.
    static func display(_ url: URL) -> String {
        let string = url.absoluteString
        guard let range = string.range(of: "://") else { return string }
        return String(string[range.upperBound...])
    }
}

// MARK: - Previews -

private let previewURL = URL(string: "https://app.flipcash.com/chat/invite#s=kQ3vR8mZp4LwN2yTb7cXe1aFhJ6sDg0uVq5oIrKxT9a")!

#Preview("Invite link, current") {
    Background(color: .backgroundMain) {
        InviteLinkPanel(pill: .link(previewURL), meta: "Expires Nov 3 · 0 joined").padding(20)
    }
}

#Preview("Invite link, creating") {
    Background(color: .backgroundMain) {
        InviteLinkPanel(pill: .creating, meta: nil).padding(20)
    }
}
