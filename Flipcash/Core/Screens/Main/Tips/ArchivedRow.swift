//
//  ArchivedRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The first row under the chips, shown whenever a chat is archived. Its trailing count is the
/// unread, non-muted archived chats, in the secondary colour so it does not read as a badge.
struct ArchivedRow: View {

    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Secondary throughout: a way into a folder, quieter than the chats below it.
                Image(systemName: "archivebox")
                    .frame(minWidth: 45)
                Text("Archived")
                    .font(.appTextMedium)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.appTextSmall)
                }
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 12)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "Archived, \(count) unread" : "Archived")
        .accessibilityIdentifier("chat-archived-row")
    }
}

/// "Chat archived" with a tappable Undo. The screen owns its lifetime; a swipe down calls `onDismiss`.
struct ArchiveUndoToast: View {

    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        FloatingToast(
            "Chat archived",
            systemImage: "archivebox",
            action: .init("Undo", accessibilityIdentifier: "chat-archive-undo", handler: onUndo),
            onDismiss: onDismiss
        )
    }
}
