//
//  ChatActionRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// One choice on a screen that is nothing but choices — a glyph and a label on a filled card
/// (nodes 10127:118000 and 10127:118327).
///
/// The chats flow has two of these screens and they are drawn identically, so the row is shared
/// rather than written twice.
struct ChatActionRow: View {

    let icon: Image
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.textMain)

                Text(title)
                    .font(.default(size: 17, weight: .bold))
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundRow, in: .rect(cornerRadius: Metrics.buttonRadius))
            .contentShape(.rect(cornerRadius: Metrics.buttonRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
