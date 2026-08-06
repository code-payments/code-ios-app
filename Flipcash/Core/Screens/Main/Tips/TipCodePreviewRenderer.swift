//
//  TipCodePreviewRenderer.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// A pair of rendered images for the tip code share sheet header: a wide hero
/// and a square icon.
struct TipCodePreview {
    let hero: UIImage
    let icon: UIImage
}

/// Renders a tip code into share sheet preview images ahead of the share tap.
///
/// Everything downstream — the cache, the item source, the call site — depends
/// only on this protocol, so a future CMP-backed renderer can drop in without
/// touching them.
protocol TipCodePreviewRenderer {
    /// Returns the hero and icon preview for `payload`, or `nil` if rendering fails.
    @MainActor func render(_ payload: TipCode.Payload) async -> TipCodePreview?
}

/// Renders the preview with `ImageRenderer` over `TipCodeShareCard`.
struct SwiftUITipCodePreviewRenderer: TipCodePreviewRenderer {

    @MainActor
    func render(_ payload: TipCode.Payload) async -> TipCodePreview? {
        let codeData = payload.codeData()

        guard
            let hero = image(.hero, codeData: codeData),
            let icon = image(.icon, codeData: codeData)
        else {
            return nil
        }

        return TipCodePreview(hero: hero, icon: icon)
    }

    @MainActor
    private func image(_ layout: TipCodeShareCard.Layout, codeData: Data) -> UIImage? {
        let renderer = ImageRenderer(content: TipCodeShareCard(layout: layout, codeData: codeData))
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// Caches rendered tip code previews so the share sheet never renders on the tap.
///
/// Keyed by the tip code's user identifier. `warm(_:)` kicks off rendering
/// eagerly when the card is displayed; `preview(for:)` is a non-blocking read at
/// share time that returns `nil` until the render completes.
@MainActor
final class TipCodePreviewCache {

    private let renderer: TipCodePreviewRenderer
    private var previews: [UserID: TipCodePreview] = [:]
    private var tasks: [UserID: Task<Void, Never>] = [:]

    init(renderer: TipCodePreviewRenderer = SwiftUITipCodePreviewRenderer()) {
        self.renderer = renderer
    }

    /// Renders and stores the preview for `payload` unless one already exists or
    /// is already in flight.
    func warm(_ payload: TipCode.Payload) {
        let userID = payload.userID
        guard previews[userID] == nil, tasks[userID] == nil else { return }

        tasks[userID] = Task { [weak self] in
            guard let self else { return }
            let preview = await renderer.render(payload)
            tasks[userID] = nil
            guard !Task.isCancelled, let preview else { return }
            previews[userID] = preview
        }
    }

    /// The cached preview for `userID`, or `nil` if it is not ready yet.
    func preview(for userID: UserID) -> TipCodePreview? {
        previews[userID]
    }

    /// Drops any cached or in-flight preview for `userID` so the next display
    /// re-renders — call on regenerate, redeem, or expiry.
    func invalidate(_ userID: UserID) {
        tasks[userID]?.cancel()
        tasks[userID] = nil
        previews[userID] = nil
    }
}
