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

/// "Chat archived" with a tappable Undo, in the undo-toast design shared with Android: a full-width
/// frosted pill. The screen owns its lifetime; a swipe down calls `onDismiss`.
struct ArchiveUndoToast: View {

    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 18))
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
            Text("Chat archived")
                .font(.default(size: 14, weight: .medium))
                .foregroundStyle(Color.textMain)
            Spacer(minLength: 0)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat-archive-undo")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 12)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 24 || value.predictedEndTranslation.height > 60 {
                        onDismiss()
                    } else {
                        withAnimation(.spring) { dragOffset = 0 }
                    }
                }
        )
    }
}
