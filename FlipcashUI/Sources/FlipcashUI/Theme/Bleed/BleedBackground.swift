//
//  BleedBackground.swift
//  FlipcashUI
//

import SwiftUI

/// A container that resolves an image's bleed palette, paints `palette.background` behind its
/// content, and provides `\.bleedPalette` to the content.
public struct BleedBackground<Content: View>: View {

    let key: String?
    let image: UIImage?
    var settings: BleedSettings
    var ignoresSafeArea: Bool
    @ViewBuilder let content: Content

    /// A background colored from `image`, cached under `key`.
    public init(
        key: String?,
        image: UIImage?,
        settings: BleedSettings = .default,
        ignoresSafeArea: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.key = key
        self.image = image
        self.settings = settings
        self.ignoresSafeArea = ignoresSafeArea
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                if ignoresSafeArea {
                    BleedFill().ignoresSafeArea()
                } else {
                    BleedFill()
                }
            }
            .bleedPalette(key: key, image: image, settings: settings)
    }
}

/// Fills its frame with the environment's `bleedPalette.background`.
public struct BleedFill: View {

    @Environment(\.bleedPalette) private var palette

    /// A fill of the palette's background.
    public init() {}

    public var body: some View {
        Rectangle().fill(palette.background)
    }
}
