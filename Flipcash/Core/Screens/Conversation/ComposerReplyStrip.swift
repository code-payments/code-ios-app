//
//  ComposerReplyStrip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The quoted original above the composer while a reply is being written. Sits inside the bottom
/// bar's background rather than on top of it, so the bar reads as one surface that grew, and
/// dismissing it takes back the target without touching the draft.
struct ComposerReplyStrip: View {

    let target: ComposerModel.ReplyTarget
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The leading rule is the quote's whole identity here; the panel has no fill of its own.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.authorName)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                Text(target.snippet)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: SystemSymbol.close.rawValue)
                    .font(.default(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replying to \(target.authorName): \(target.snippet)")
    }
}
