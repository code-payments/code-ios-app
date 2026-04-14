//
//  CurrencyCreationHeroAnchor.swift
//  Flipcash
//
//  Layout-driven hero positioning for the currency creation wizard.
//  The non-sliding controls layer and the icon chrome's Menu publish
//  Anchor<CGRect> rects via `.heroAnchor(_:)`. The HeroLayer overlay
//  reads those anchors and positions independent circle + name views.
//

import SwiftUI

enum HeroAnchorID: Hashable {
    case circle
    case name
    case bill
}

struct HeroAnchorKey: PreferenceKey {
    static let defaultValue: [HeroAnchorID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [HeroAnchorID: Anchor<CGRect>],
        nextValue: () -> [HeroAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publishes this view's bounds as the anchor for the given hero ID.
    /// Attach to either an invisible `HeroPlaceholder` (non-sliding
    /// controls layer) or to the actual interactive control (Menu on
    /// icon chrome, TextField on name controls).
    func heroAnchor(_ id: HeroAnchorID) -> some View {
        anchorPreference(key: HeroAnchorKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}
