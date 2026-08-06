//
//  TipCodeShareCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A fixed-frame, environment-free rendering of a tip code for the share sheet
/// preview: the scannable code centered on an opaque black background.
///
/// Deliberately deterministic — an explicit size and a hardcoded color scheme —
/// so `ImageRenderer` produces the same image regardless of the trait
/// environment it is invoked from.
struct TipCodeShareCard: View {

    /// The two preview surfaces iOS shows in the share sheet header.
    enum Layout {
        /// The wide hero image behind the large link preview (~1200×630).
        case hero
        /// The square image used for the compact icon; recomposed rather than
        /// cropped from the hero so the code stays centered.
        case icon

        var size: CGSize {
            switch self {
            case .hero: CGSize(width: 1200, height: 630)
            case .icon: CGSize(width: 1080, height: 1080)
            }
        }
    }

    let layout: Layout
    let codeData: Data

    var body: some View {
        let canvas = layout.size
        let codeSide = min(canvas.width, canvas.height) * 0.6

        ZStack {
            Color.black
            CodeView(data: codeData)
                .foregroundStyle(Color.white)
                .frame(width: codeSide, height: codeSide)
        }
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, .dark)
    }
}
