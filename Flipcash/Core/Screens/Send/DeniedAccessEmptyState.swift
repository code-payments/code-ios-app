//
//  DeniedAccessEmptyState.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Shown in the Send sheet when contact access is denied **and** there are no
/// recent chats to fall back on. A ghosted cash-card-and-chat illustration sells
/// the feature, three bullets address the privacy objections, and the button
/// routes to Settings. Rendered in the non-searchable stack, so it has no search
/// bar (matching the design). The "Send" title and close button come from the
/// hosting `NavigationStack`.
struct DeniedAccessEmptyState: View {

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            SendConversationHero()

            VStack(spacing: 8) {
                Text("Send Money to Your Friends")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                Text("Sync your contacts to find, invite, and pay friends.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 28)

            Spacer(minLength: 24)

            // Hugs its content so the parent `VStack` centers the block; the
            // rows stay leading-aligned to each other (icons in one column).
            VStack(alignment: .leading, spacing: 22) {
                PermissionBulletRow(icon: .checklist, text: "You decide which contacts to add")
                PermissionBulletRow(icon: .lock, text: "Your information is always secure")
                PermissionBulletRow(icon: .peopleGear, text: "Change contact access at any time")
            }

            Spacer(minLength: 0)

            Button("Allow Contact Access in Settings") {
                URL.openSettings()
            }
            .buttonStyle(.filled)
        }
        .padding(20)
    }
}

/// One reassurance bullet: a tinted glyph and a line of copy.
private struct PermissionBulletRow: View {

    let icon: Asset
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image.asset(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.textMain)
            Text(text)
                .font(.appTextMessage)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview -

#Preview {
    NavigationStack {
        DeniedAccessEmptyState()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.backgroundMain)
            .navigationTitle("Send")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
            }
    }
    .preferredColorScheme(.dark)
}
