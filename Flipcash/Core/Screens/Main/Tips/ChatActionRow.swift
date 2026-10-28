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
    /// The card's fill: ``Color/backgroundRow`` over the main background, lighter on a lifted sheet.
    var background: Color = .backgroundRow
    /// The icon and title colour: ``Color/textError`` for a destructive row.
    var tint: Color = .textMain
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(tint)

                Text(title)
                    .font(.default(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: .rect(cornerRadius: Metrics.buttonRadius))
            .contentShape(.rect(cornerRadius: Metrics.buttonRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
