//
//  BleedColorStore.swift
//  FlipcashUI
//

import SwiftUI

/// Main-actor cache of extracted bleed colors, keyed by a caller-supplied id, and of the palettes
/// built from them. Extraction runs off the main actor and is de-duplicated while in flight.
///
/// Each id has its own observable box, so a view re-renders only when its own color resolves.
final class BleedColorStore {

    /// The shared store.
    static let shared = BleedColorStore()

    private struct PaletteKey: Hashable {
        let base: BleedRGB
        let settings: BleedSettings
    }

    private var colors: [String: ObservableBox<BleedRGB>] = [:]
    private var inFlight: [String: Task<BleedRGB?, Never>] = [:]
    /// Palettes are pure functions of (color, settings); building one runs OKLab conversions, a
    /// gamut search and contrast loops, so each is built once.
    private var palettes: [PaletteKey: BleedPalette] = [:]

    /// The cached color for `id`, or `nil` before it resolves.
    func color(for id: String) -> BleedRGB? {
        box(for: id).value
    }

    /// The palette for an extracted color, memoized.
    func palette(for base: BleedRGB, settings: BleedSettings) -> BleedPalette {
        let key = PaletteKey(base: base, settings: settings)
        if let palette = palettes[key] { return palette }
        let palette = BleedPalette(base: base, settings: settings)
        palettes[key] = palette
        return palette
    }

    /// Computes the color of `image` once under `id` and caches it; safe to call from `.task(id:)`
    /// on every appearance.
    @discardableResult
    func resolve(_ id: String, image: UIImage) async -> BleedRGB? {
        let box = box(for: id)
        if let cached = box.value { return cached }

        let task: Task<BleedRGB?, Never>
        if let existing = inFlight[id] {
            task = existing
        } else {
            task = Task { await BleedColorExtractor.extract(image: image) }
            inFlight[id] = task
        }
        let result = await task.value
        inFlight[id] = nil

        if let result, box.value == nil {
            withAnimation(.easeOut(duration: 0.25)) {
                box.value = result
            }
        }
        return result
    }

    private func box(for id: String) -> ObservableBox<BleedRGB> {
        if let box = colors[id] { return box }
        let box = ObservableBox<BleedRGB>()
        colors[id] = box
        return box
    }
}
