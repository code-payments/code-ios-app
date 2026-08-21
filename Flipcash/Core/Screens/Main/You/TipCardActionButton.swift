//
//  TipCardActionButton.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// One of the two large tip-card actions under the link row — Share or Download
/// (Figma node 9276:4756): a 28pt glyph over a dimmed caption, filling half the
/// row.
struct TipCardActionButton: View {

    let asset: Asset
    let title: String
    let action: VoidAction

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image.asset(asset)
                    .renderingMode(.template)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color.textMain)

                Text(title)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .opacity(0.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
