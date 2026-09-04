//
//  ComposerReplyStrip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The quoted original above the composer while a reply is being written. It paints no background of
/// its own: the bar draws one opaque surface behind the quote and the controls together, so the two
/// read as one panel rather than a strip parked above a bar. Dismissing it takes back the target
/// without touching the draft.
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
            // Combined here rather than on the row, so the quote reads as one element while the
            // dismiss button stays a button of its own — a row-level combine folds the button into
            // the label and leaves nothing to press.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Replying to \(target.authorName): \(target.snippet)")
            .accessibilityIdentifier("composer-reply-quote")

            Button(action: onDismiss) {
                Image(systemName: SystemSymbol.close.rawValue)
                    .font(.default(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
            .accessibilityIdentifier("cancel-reply-button")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer-reply-strip")
    }
}
