//
//  TokenBillStyle.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// How a token's bill is painted, in one place.
///
/// The bill is drawn twice in the app — `TokenCardView` in SwiftUI for the wallet deck and the
/// token screen, and `LinkCashCardView` in UIKit for a cash link in the transcript, which recycles
/// and so does not host SwiftUI. Two renderers is a deliberate cost (see `ChatAuthorAvatarView` for
/// the same trade); two palettes would not be, so the stops are resolved here and both read them.
public enum TokenBillStyle {

    /// Figma's medium shape, the same radius the wallet card uses.
    public static let cornerRadius: CGFloat = Metrics.boxRadius

    /// A token with no bill customization of its own.
    public static let fallback = "#06450F"

    /// The proportions of the wallet's bill: 224pt of card across 328pt of usable width — its own
    /// height at full width less two screen insets on a 375pt phone. A chat bubble is a good deal
    /// narrower than that, and scaling the height with the width is what keeps the card a bill
    /// there instead of a tall panel.
    public static let aspectRatio: CGFloat = 224.0 / 328.0

    /// The gradient's stops, leading to trailing, as `#RRGGBB`.
    ///
    /// The reserve's gold is sourced from the model rather than restated, so the Dollars card, its
    /// give bill and a Dollars link card cannot drift apart. A single customization color yields a
    /// flat fill rather than a gradient to nowhere.
    public static func stops(colors: [String], isUSDF: Bool) -> [String] {
        if isUSDF {
            return MintMetadata.usdf.billColors
        }
        switch colors.count {
        case 0:  return [fallback, fallback]
        case 1:  return [colors[0], colors[0]]
        default: return colors
        }
    }

    /// The same stops as `Color`.
    public static func colorStops(colors: [String], isUSDF: Bool) -> [Color] {
        let parsed = stops(colors: colors, isUSDF: isUSDF).compactMap(Color.init(hex:))
        switch parsed.count {
        case 0:  return [Color(hex: fallback)!, Color(hex: fallback)!]
        case 1:  return [parsed[0], parsed[0]]
        default: return parsed
        }
    }
}
