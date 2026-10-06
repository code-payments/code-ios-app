//
//  ProfileCoverFill.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The solid colour a cover banner shows when the profile has no cover picture.
enum ProfileCoverFill {

    /// The card tone used when a profile carries no colour, or one that doesn't parse.
    static let fallback = Color.backgroundRow

    /// The customization's colour, or ``fallback`` when it is absent or not a `#RRGGBB` hex.
    static func color(for customization: TipCardCustomization?) -> Color {
        customization.flatMap { Color(hex: $0.colorHex) } ?? fallback
    }
}
