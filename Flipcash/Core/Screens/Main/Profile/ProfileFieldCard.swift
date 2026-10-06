//
//  ProfileFieldCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A tappable card with the field's title over its current value, styled like the profile's stats card.
struct FieldCard: View {

    let title: String
    let value: String?
    let placeholder: String
    var valueIsPrompt = false
    var lineLimit = 1
    let action: VoidAction

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(value ?? placeholder)
                        .font(.appTextMedium)
                        .foregroundStyle(value == nil || valueIsPrompt ? Color.textSecondary : Color.textMain)
                        .lineLimit(lineLimit)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The "Change cover" button over the cover photo: an interactive Liquid Glass capsule on iOS 26, and on iOS 18 an
/// opaque chip, since the standard chip's row fill is translucent and vanishes on a photo.
struct CoverChip: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(Color.backgroundMain.opacity(0.6)).interactive(), in: .capsule)
        } else {
            content.chip(.tinted(.textMain, on: .backgroundMain))
        }
    }
}
