//
//  StackedPeopleIcon.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Leading glyph for the "Add More Contacts" footer: three overlapping
/// avatar-gradient circles — two people silhouettes behind a front "+" —
/// echoing a stack of contacts waiting to be added. Built from
/// `LinearGradient.avatarPlaceholder` so it stays in sync with the contact
/// avatars.
struct StackedPeopleIcon: View {

    var circleSize: CGFloat = 44

    private var step: CGFloat { circleSize * 0.45 }

    var body: some View {
        ZStack(alignment: .leading) {
            GradientGlyphCircle(size: circleSize) { PeopleSilhouette(size: circleSize) }
                .offset(x: step * 2)

            GradientGlyphCircle(size: circleSize) { PeopleSilhouette(size: circleSize) }
                .offset(x: step)

            GradientGlyphCircle(size: circleSize) {
                Image(systemName: "plus")
                    .font(.system(size: circleSize * 0.42, weight: .semibold))
                    .foregroundStyle(Color.textMain)
            }
        }
        .frame(width: circleSize + step * 2, height: circleSize, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// An avatar-gradient circle hosting a single glyph, ringed in the screen
/// background so stacked circles read as cleanly separated.
private struct GradientGlyphCircle<Glyph: View>: View {

    let size: CGFloat
    @ViewBuilder let glyph: Glyph

    var body: some View {
        LinearGradient.avatarPlaceholder
            .frame(width: size, height: size)
            .overlay { glyph }
            .clipShape(Circle())
            .overlay {
                Circle().stroke(Color.backgroundMain, lineWidth: 2)
            }
    }
}

#Preview {
    StackedPeopleIcon()
        .padding()
        .background(Color.backgroundMain)
}
