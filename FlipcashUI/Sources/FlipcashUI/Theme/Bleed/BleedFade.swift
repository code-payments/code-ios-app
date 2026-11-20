//
//  BleedFade.swift
//  FlipcashUI
//

import SwiftUI

/// The image-to-color fade at the bottom of a bleed image: `color` eases in over `height` on the
/// smootherstep curve, then keeps going, solid, `seamOverlap` past the image's bottom and side edges.
///
/// The overhang keeps the seam invisible: when the image and its fade end on the same edge, that
/// row is antialiased twice whenever it lands between pixels, and a hairline of the image shows
/// through. Overlay it on the clipped image, aligned to the bottom, over a page of the same color.
public struct BleedFade: View {

    let color: Color
    /// The length of the eased ramp, ending at the image's bottom edge.
    let height: CGFloat

    /// How far the solid color runs past the image's bottom and side edges.
    static let seamOverlap: CGFloat = 2

    /// A fade of `color` over `height`.
    public init(color: Color, height: CGFloat) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        let overlap = Self.seamOverlap
        let total = max(height, 0) + overlap

        // One gradient for the ramp and the overhang: a solid strip butted against the ramp's end
        // would be the same coincident edge again, one layer up.
        LinearGradient(
            stops: EasedStops.fade(to: color, end: max(height, 0) / total),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: total)
        .padding(.horizontal, -overlap)
        .padding(.bottom, -overlap)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
