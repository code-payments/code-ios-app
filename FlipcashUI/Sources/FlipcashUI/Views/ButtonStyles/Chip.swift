//
//  Chip.swift
//  FlipcashUI
//

import SwiftUI

/// Visual style for a compact chip label: what colour its text and fill take, and what shape the
/// fill draws.
///
/// A struct of statics rather than an enum so a caller can name a colour the theme doesn't have a
/// chip token for. ``tinted(_:on:)`` is one line where a case would have been a new name, a new colour
/// constant, and a switch arm in two places — all for a single use.
public struct ChipStyle {

    let textColor: Color
    let fillColor: Color
    let shape: AnyShape

    private init(textColor: Color, fillColor: Color, shape: some Shape) {
        self.textColor = textColor
        self.fillColor = fillColor
        self.shape = AnyShape(shape)
    }

    /// Subtle row-fill background — e.g. the "Invite" affordance.
    public static let standard = ChipStyle(
        textColor: .textMain,
        fillColor: .backgroundRow,
        shape: RoundedRectangle(cornerRadius: Metrics.buttonRadius)
    )

    /// Solid white fill — e.g. the "Settings" affordance.
    public static let prominent = ChipStyle(
        textColor: .backgroundMain,
        fillColor: .textMain,
        shape: RoundedRectangle(cornerRadius: Metrics.buttonRadius)
    )

    /// `color` on its own muted ground, in a capsule — for a chip that reports state rather than
    /// offering an action.
    ///
    /// The colour lands in the fill rather than only in the text: at full strength on the row fill
    /// a tinted label out-shouts the title above it, which inverts the hierarchy on a screen whose
    /// subject is the chat, not the viewer's settings. The capsule is the other half of that —
    /// ``Metrics/buttonRadius`` is the corner every button on the screen uses, so a rounded rect
    /// invites a tap this chip has nothing to do with.
    ///
    /// `fill` is named rather than derived here because the theme owns what a colour's muted ground
    /// is — see ``ShapeStyle/warningSecondary`` and the sentiment pair secondaries, which are flat
    /// values rather than an opacity on their main colour.
    public static func tinted(_ color: Color, on fill: Color) -> ChipStyle {
        ChipStyle(textColor: color, fillColor: fill, shape: Capsule())
    }
}

public extension View {
    /// Styles the receiver as a compact chip: a small bold label on its own fill. Used for the
    /// non-interactive affordance inside a tappable row (the whole row is the tap target), e.g.
    /// "Invite" and "Settings", and for a standalone status chip via ``ChipStyle/tinted(_:on:)``.
    func chip(_ style: ChipStyle) -> some View {
        self
            .font(.appTextSmall)
            .foregroundStyle(style.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                style.shape.fill(style.fillColor)
            }
    }
}
