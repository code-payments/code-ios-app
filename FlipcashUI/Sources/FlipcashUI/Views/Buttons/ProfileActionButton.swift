//
//  ProfileActionButton.swift
//  FlipcashUI
//

import SwiftUI

/// A circular glyph over a caption, used for a profile's own row of actions (Message, Send Cash)
/// and reused wherever a screen wants that same tile — e.g. the group invite sheet's Share and
/// Copy Link actions.
public struct ProfileActionButton<Glyph: View>: View {

    let title: String
    @ViewBuilder let glyph: Glyph
    let action: () -> Void

    private var diameter: CGFloat { 45 }
    /// The column each button owns, so a row of them keeps fixed centers as buttons come and go.
    private var columnWidth: CGFloat { 100 }

    public init(title: String, @ViewBuilder glyph: () -> Glyph, action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                glyph
                    .foregroundStyle(.textMain)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(.backgroundSecondary))

                // One line even past the column, so a longer caption ("Copy Invite Link") doesn't
                // wrap and lift its glyph above its neighbours'.
                Text(title)
                    .font(.appTextSmall)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: columnWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}
