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
                Image(systemName: "archivebox")
                    .frame(minWidth: 45)
                Text("Archived")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "Archived, \(count) unread" : "Archived")
        .accessibilityIdentifier("chat-archived-row")
    }
}

/// "Chat archived" with a tappable Undo. `ToastLabel` is text-only, so this is its own small view in
/// the same capsule treatment; the screen dismisses it with a timer.
struct ArchiveUndoToast: View {

    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Chat archived")
                .foregroundStyle(Color.textMain)
            Button("Undo", action: onUndo)
                .foregroundStyle(Color.textMain)
                .bold()
                .accessibilityIdentifier("chat-archive-undo")
        }
        .font(.appTextSmall)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
