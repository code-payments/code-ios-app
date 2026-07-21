//
//  CircleImage.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Shows an image clipped to a circle, or a plus glyph when there isn't one yet.
struct CircleImage: View {

    let image: UIImage?
    let size: CGFloat
    let plusSize: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.2))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "plus")
                    .font(.system(size: plusSize, weight: .light))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: size, height: size)
        // Flattens the fill and the image into one layer so the clip applies to
        // both; without it the scaledToFill image escapes the circle.
        .compositingGroup()
        .clipShape(Circle())
    }
}
