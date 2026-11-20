//
//  BleedPaletteModifier.swift
//  FlipcashUI
//

import SwiftUI

/// Resolves the bleed palette for an image and provides it to descendants as `\.bleedPalette`.
struct BleedPaletteModifier: ViewModifier {

    let key: String?
    let image: UIImage?
    let settings: BleedSettings

    /// The last color this subtree resolved, held while a better image for the same subject
    /// (a blurhash giving way to the real bytes) is still being read.
    @State private var heldColor: BleedRGB?

    func body(content: Content) -> some View {
        let store = BleedColorStore.shared
        let color = key.flatMap { store.color(for: $0) } ?? heldColor
        let palette = color.map { store.palette(for: $0, settings: settings) } ?? .placeholder

        content
            .environment(\.bleedPalette, palette)
            .task(id: key) {
                guard let key, let image else { return }
                if let resolved = await store.resolve(key, image: image) {
                    heldColor = resolved
                }
            }
    }
}

extension View {

    /// Provides `\.bleedPalette` for `image` to this subtree, computing its color asynchronously
    /// and caching it under `key`, which must change whenever the image's pixels do. With a nil
    /// `key` or `image` the subtree gets the placeholder palette. Draws nothing itself.
    public func bleedPalette(key: String?, image: UIImage?, settings: BleedSettings = .default) -> some View {
        modifier(BleedPaletteModifier(key: key, image: image, settings: settings))
    }
}
