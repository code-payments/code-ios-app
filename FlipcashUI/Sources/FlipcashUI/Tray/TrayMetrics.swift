//
//  TrayMetrics.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit

/// The tray's layout, type and fill values: the Modals v2 mockup (Figma `552:811`), retuned on
/// the Dev iPhone in rounds 2–4.
@MainActor
enum TrayMetrics {

    // MARK: - Layout

    static let padding: CGFloat = 24
    static let iconToTitle: CGFloat = 12
    static let titleToBody: CGFloat = 12
    static let bodyToContent: CGFloat = 16
    static let contentToActions: CGFloat = 24
    static let iconSize: CGFloat = 64
    static let closeSize: CGFloat = 36
    /// The drawn extent of the close X, edge to edge.
    static let closeGlyphSize: CGFloat = 12
    static let closeStroke: CGFloat = 2.5
    static let closeGlyphOpacity: Double = 1.0
    static let closeFillOpacity: Double = 0.05
    static let actionHeight: CGFloat = 54
    static let actionGap: CGFloat = 12
    /// The card's top corners on the floating sheet; 39.5 draws the system sheet's 38 at the
    /// sheet's 0.96 scale. The bottom corners nest in the display's.
    static let topRadius: CGFloat = 39.5

    /// The edge-attached iOS 18 sheet's top corners, which the card matches.
    static let edgeAttachedTopRadius: CGFloat = 10

    /// The close control's tap target, wider than its drawn circle.
    static let closeHitSize: CGFloat = 44

    // MARK: - Type

    // SF Pro sizes until type tokens are decided (Phase 2). Each is the size at the default
    // Dynamic Type category and scales with the text style it stands in for.
    static let titleSize: CGFloat = 24
    /// A title in the header row, beside the X, for a step with no icon.
    static let headerTitleSize: CGFloat = 20
    static let titleWeight: Font.Weight = .semibold
    static let titleTracking: CGFloat = -0.22
    static let bodySize: CGFloat = 15
    static let bodyLineHeight: CGFloat = 20
    static let bodyOpacity: Double = 0.6
    static let actionSize: CGFloat = 16

    /// `size` at `dynamicTypeSize`, scaled as `style` scales; `size` itself at the default
    /// category.
    static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle, _ dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        return UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
    }

    /// The extra space between body lines that brings SF's natural line height up to the target
    /// at `dynamicTypeSize`.
    static func bodyLineSpacing(_ dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let size = scaled(bodySize, .subheadline, dynamicTypeSize)
        let lineHeight = scaled(bodyLineHeight, .subheadline, dynamicTypeSize)
        return max(0, lineHeight - UIFont.systemFont(ofSize: size).lineHeight)
    }

    // MARK: - Fill

    /// Whether the card is Liquid Glass (iOS 26+) or a material (iOS 18) instead of the flat fill.
    static let usesGlass = false
    static let flatOpacity: Double = 0.5
    /// Whether the system dims the screen behind the tray.
    static let dimsBackground = true

    // MARK: - Rows

    static let rowHeight: CGFloat = 56
    static let rowRadius: CGFloat = 16
    static let rowGap: CGFloat = 8
    static let rowFillOpacity: Double = 0.06
    static let rowSelectedFillOpacity: Double = 0.14
    static let rowIconSize: CGFloat = 22
    static let rowTextSize: CGFloat = 17
    static let rowTextWeight: Font.Weight = .semibold
    static let tileHeight: CGFloat = 64
    static let tileRadius: CGFloat = 16
    static let tileSelection: TrayTileSelection = .raised
    static let rowPressScale: CGFloat = 0.98

    // MARK: - Error fade

    /// The red at the error card's top edge.
    static let errorFadeStrength: Double = 0.39
    /// How far down the error card the red reaches before it's gone, as a share of the card's height.
    static let errorFadeLength: Double = 0.865
    /// How much darker the error card is than a standard tray, under the red.
    static let errorFadeDarkness: Double = 0.53

    // MARK: - Behavior

    static let actionPress: TrayActionPress = .scale
    static let actionPressScale: CGFloat = 0.95
    static let actionPressDim: Double = 0.7
}

/// How a selected tile stands out.
enum TrayTileSelection {
    /// The row's raised fill.
    case raised
    /// A white ring on the resting fill.
    case outline
    /// White, with a dark label, as the primary CTA.
    case inverted
}

/// How the CTA answers a press.
enum TrayActionPress {
    case none, scale, dim

    /// The press to draw: Reduce Motion turns a scale into a dim, keeping feedback without
    /// movement.
    func resolved(reduceMotion: Bool) -> TrayActionPress {
        switch self {
        case .scale: reduceMotion ? .dim : .scale
        case .none, .dim: self
        }
    }
}
