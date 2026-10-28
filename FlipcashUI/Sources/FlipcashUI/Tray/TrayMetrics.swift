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
///
/// Every value is live in the tuner during the feel round and bakes back to a constant in Phase 2.
@MainActor
enum TrayMetrics {

    // MARK: - Layout

    static var padding: CGFloat { layout("Padding", 24, 0...48) } // LOCAL-TUNER
    static var iconToTitle: CGFloat { layout("Icon → title", 12, 0...40) } // LOCAL-TUNER
    static var titleToBody: CGFloat { layout("Title → body", 12, 0...32) } // LOCAL-TUNER
    static var bodyToContent: CGFloat { layout("Body → content", 16, 0...40) } // LOCAL-TUNER
    static var contentToActions: CGFloat { layout("Content → CTA", 24, 0...48) } // LOCAL-TUNER
    static var iconSize: CGFloat { layout("Icon size", 64, 0...96) } // LOCAL-TUNER
    static var closeSize: CGFloat { layout("Close size", 36, 24...48) } // LOCAL-TUNER
    /// The drawn extent of the close X, edge to edge.
    static var closeGlyphSize: CGFloat { layout("Close glyph", 12, 6...20) } // LOCAL-TUNER
    static var closeStroke: CGFloat { layout("Close stroke", 2.5, 1...4) } // LOCAL-TUNER
    static var closeGlyphOpacity: Double { Tuner.shared.value("Tray Layout/Close glyph opacity", default: 1.0, in: 0...1) } // LOCAL-TUNER
    static var closeFillOpacity: Double { Tuner.shared.value("Tray Layout/Close fill opacity", default: 0.05, in: 0...0.3) } // LOCAL-TUNER
    static var actionHeight: CGFloat { layout("CTA height", 54, 36...64) } // LOCAL-TUNER
    static var actionGap: CGFloat { layout("CTA gap", 12, 0...24) } // LOCAL-TUNER
    /// The card's top corners on the floating sheet; 39.5 draws the system sheet's 38 at the
    /// sheet's 0.96 scale. The bottom corners nest in the display's.
    static var topRadius: CGFloat { layout("Top radius", 39.5, 0...60) } // LOCAL-TUNER

    /// The edge-attached iOS 18 sheet's top corners, which the card matches.
    static let edgeAttachedTopRadius: CGFloat = 10

    /// The close control's tap target, wider than its drawn circle.
    static let closeHitSize: CGFloat = 44

    // MARK: - Type

    // SF Pro sizes until type tokens are decided (Phase 2). Each is the size at the default
    // Dynamic Type category and scales with the text style it stands in for.
    static var titleSize: CGFloat { type("Title size", 24, 14...34) } // LOCAL-TUNER
    /// A title in the header row, beside the X, for a step with no icon.
    static var headerTitleSize: CGFloat { type("Header title size", 20, 14...28) } // LOCAL-TUNER
    static var titleWeight: Font.Weight { Tuner.shared.value("Tray Type/Title weight", default: TrayTitleWeight.semibold).weight } // LOCAL-TUNER
    static var titleTracking: CGFloat { type("Title tracking", -0.22, -2...2) } // LOCAL-TUNER
    static var bodySize: CGFloat { type("Body size", 15, 10...20) } // LOCAL-TUNER
    static var bodyLineHeight: CGFloat { type("Body line height", 20, 12...30) } // LOCAL-TUNER
    static var bodyOpacity: Double { Tuner.shared.value("Tray Type/Body opacity", default: 0.6, in: 0...1) } // LOCAL-TUNER
    static var bodyStyle: TrayBodyStyle { Tuner.shared.value("Tray Type/Body style", default: TrayBodyStyle.vibrant) } // LOCAL-TUNER
    static var actionSize: CGFloat { type("CTA size", 16, 12...22) } // LOCAL-TUNER

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
    static var usesGlass: Bool { Tuner.shared.value("Tray Fill/Liquid Glass", default: false) } // LOCAL-TUNER
    static var flatOpacity: Double { Tuner.shared.value("Tray Fill/Flat opacity", default: 0.5, in: 0...1) } // LOCAL-TUNER
    /// Whether the system dims the screen behind the tray.
    static var dimsBackground: Bool { Tuner.shared.value("Tray Fill/System dim", default: true) } // LOCAL-TUNER

    // MARK: - Rows

    static var rowHeight: CGFloat { Tuner.shared.value("Tray Rows/Height", default: 56, in: 40...72, unit: .points) } // LOCAL-TUNER
    static var rowRadius: CGFloat { Tuner.shared.value("Tray Rows/Radius", default: 16, in: 0...36, unit: .points) } // LOCAL-TUNER
    static var rowGap: CGFloat { Tuner.shared.value("Tray Rows/Gap", default: 8, in: 0...20, unit: .points) } // LOCAL-TUNER
    static var rowFillOpacity: Double { Tuner.shared.value("Tray Rows/Fill opacity", default: 0.06, in: 0...0.3) } // LOCAL-TUNER
    static var rowSelectedFillOpacity: Double { Tuner.shared.value("Tray Rows/Selected fill opacity", default: 0.14, in: 0...0.4) } // LOCAL-TUNER
    static var rowIconSize: CGFloat { Tuner.shared.value("Tray Rows/Icon size", default: 22, in: 14...32, unit: .points) } // LOCAL-TUNER
    static var rowTextSize: CGFloat { Tuner.shared.value("Tray Rows/Text size", default: 17, in: 13...22, unit: .points) } // LOCAL-TUNER
    static var rowTextWeight: Font.Weight { Tuner.shared.value("Tray Rows/Text weight", default: TrayTitleWeight.semibold).weight } // LOCAL-TUNER
    static var tileHeight: CGFloat { Tuner.shared.value("Tray Rows/Tile height", default: 64, in: 44...96, unit: .points) } // LOCAL-TUNER
    static var tileRadius: CGFloat { Tuner.shared.value("Tray Rows/Tile radius", default: 16, in: 0...36, unit: .points) } // LOCAL-TUNER
    static var tileSelection: TrayTileSelection { Tuner.shared.value("Tray Rows/Tile selection", default: TrayTileSelection.raised) } // LOCAL-TUNER
    static var rowHaptic: TrayRowHaptic { Tuner.shared.value("Tray Rows/Haptic", default: TrayRowHaptic.selection) } // LOCAL-TUNER
    static var rowPressScale: CGFloat { Tuner.shared.value("Tray Rows/Press scale", default: 0.98, in: 0.9...1) } // LOCAL-TUNER

    // MARK: - Error fade

    // The keys keep the "Tray Destructive" group the app's floating tuner lists. // LOCAL-TUNER
    /// The red at the error card's top edge.
    static var errorFadeStrength: Double { Tuner.shared.value("Tray Destructive/Fade strength", default: 0.39, in: 0...1) } // LOCAL-TUNER
    /// How far down the error card the red reaches before it's gone, as a share of the card's height.
    static var errorFadeLength: Double { Tuner.shared.value("Tray Destructive/Fade length", default: 0.865, in: 0.1...1) } // LOCAL-TUNER
    /// How much darker the error card is than a standard tray, under the red.
    static var errorFadeDarkness: Double { Tuner.shared.value("Tray Destructive/Fade card darkness", default: 0.53, in: 0...1) } // LOCAL-TUNER

    // MARK: - Behavior

    static var actionPress: TrayActionPress { Tuner.shared.value("Tray Behavior/CTA press", default: TrayActionPress.scale) } // LOCAL-TUNER
    static var actionPressScale: CGFloat { Tuner.shared.value("Tray Behavior/CTA press scale", default: 0.95, in: 0.9...1) } // LOCAL-TUNER
    static var actionPressDim: Double { Tuner.shared.value("Tray Behavior/CTA press dim", default: 0.7, in: 0.3...1) } // LOCAL-TUNER

    // MARK: - Tuner

    private static func layout(_ name: String, _ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        Tuner.shared.value("Tray Layout/\(name)", default: value, in: range, unit: .points) // LOCAL-TUNER
    }

    private static func type(_ name: String, _ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        Tuner.shared.value("Tray Type/\(name)", default: value, in: range, unit: .points) // LOCAL-TUNER
    }
}

/// The title weights the tuner offers.
enum TrayTitleWeight: TunableEnum { // LOCAL-TUNER: conformance
    case regular, medium, semibold, bold, heavy

    var weight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }
}

/// The body text's ink.
enum TrayBodyStyle: TunableEnum { // LOCAL-TUNER: conformance
    /// White at the body opacity.
    case flat
    /// White at the body opacity, blended plus-lighter so the card's colour shows through.
    case vibrant
    /// SwiftUI's `.secondary` hierarchical style.
    case hierarchical
}

/// How a selected tile stands out.
enum TrayTileSelection: TunableEnum { // LOCAL-TUNER: conformance
    /// The row's raised fill.
    case raised
    /// A white ring on the resting fill.
    case outline
    /// White, with a dark label, as the primary CTA.
    case inverted
}

/// The haptic a tray row plays on tap.
enum TrayRowHaptic: TunableEnum { // LOCAL-TUNER: conformance
    case none, selection, softest, soft, medium

    /// Kept prepared between taps, so fast typing gets its haptic on time.
    @MainActor private static let selectionGenerator = UISelectionFeedbackGenerator()

    @MainActor func play() {
        switch self {
        case .none: break
        case .selection:
            Self.selectionGenerator.selectionChanged()
            Self.selectionGenerator.prepare()
        case .softest: Haptics.softest()
        case .soft: Haptics.soft()
        case .medium: Haptics.medium()
        }
    }
}

/// How the CTA answers a press.
enum TrayActionPress: TunableEnum { // LOCAL-TUNER: conformance
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
