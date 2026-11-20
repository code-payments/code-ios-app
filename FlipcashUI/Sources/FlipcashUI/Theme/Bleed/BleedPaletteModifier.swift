//
//  BleedPaletteModifier.swift
//  FlipcashUI
//

import SwiftUI

/// Resolves the bleed palette for an image in the current appearance and provides it to
/// descendants as `\.bleedPalette`.
struct BleedPaletteModifier: ViewModifier {

    let key: String?
    let image: UIImage?
    let settings: BleedSettings

    /// The last color this subtree resolved, held while a better image for the same subject
    /// (a blurhash giving way to the real bytes) is still being read.
    @State private var heldColor: BleedRGB?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let store = BleedColorStore.shared
        let color = key.flatMap { store.color(for: $0) } ?? heldColor
        let palette = color.map { store.palette(for: $0, settings: settings, colorScheme: colorScheme) }
            ?? .placeholder(for: colorScheme)

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

    /// Provides `\.bleedPalette` for `image` in the subtree's appearance, computing its color asynchronously
    /// and caching it under `key`, which must change whenever the image's pixels do. With a nil
    /// `key` or `image` the subtree gets the placeholder palette. Draws nothing itself.
    public func bleedPalette(key: String?, image: UIImage?, settings: BleedSettings = .default) -> some View {
        modifier(BleedPaletteModifier(key: key, image: image, settings: settings))
    }
}
