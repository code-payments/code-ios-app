//
//  BleedTextStyle.swift
//  FlipcashUI
//

import SwiftUI

/// A text color on the bleed and how it composites onto it.
///
/// Vibrant text is white drawn with `.plusLighter`, so it adds to the color behind it channel by
/// channel and the bleed's hue shows through instead of washing out to gray; flat text is the color
/// at its opacity, composited normally. Vibrant text only works drawn straight onto the bleed:
/// inside a `.compositingGroup()`, `.drawingGroup()` or a glass effect it composites against that
/// layer instead, and a run inside a concatenated `Text` loses the blend, so use the flat color there.
nonisolated struct BleedTextStyle: Hashable, Sendable {
    /// White at the style's opacity.
    var color: Color
    var blendMode: BlendMode = .normal

    /// The style for `foregroundStyle(_:)`.
    var shapeStyle: AnyShapeStyle {
        blendMode == .normal ? AnyShapeStyle(color) : AnyShapeStyle(color.blendMode(blendMode))
    }
}
