//
//  BleedPalette.swift
//  FlipcashUI
//

import SwiftUI

/// Colors for content that sits on an image's bleed color: the deep background plus text and
/// control colors chosen for contrast on it. Read it with `@Environment(\.bleedPalette)` inside a
/// `.bleedPalette(key:image:settings:)` subtree.
public struct BleedPalette: Hashable {

    /// The bleed fill: the image's bottom-edge color, pulled deep enough to carry white text.
    public var background: Color
    /// Primary text on `background`, white.
    public var primaryText: Color
    /// Secondary text as a flat color, for runs that can't take a blend mode; prefer `secondaryStyle`.
    public var secondaryText: Color
    /// Paragraph text as a flat color; prefer `bodyStyle`.
    public var bodyText: Color
    var secondaryTextStyle: BleedTextStyle
    var tertiaryTextStyle: BleedTextStyle
    var bodyTextStyle: BleedTextStyle
    /// Hairlines and dividers on `background`.
    public var hairline: Color
    var controlSecondaryTextStyle: BleedTextStyle
    /// A lifted tint of `background` for surfaces and controls over it.
    public var controlTint: Color
    /// The label color for controls filled with `controlTint`.
    public var controlLabel: Color
    /// The scheme content on the bleed renders in; always dark.
    public var colorScheme: ColorScheme
    /// The resolved background as sRGB; `nil` for the placeholder.
    var backgroundRGB: BleedRGB?

    /// Whether the palette was derived from an image rather than being the placeholder.
    public var isResolved: Bool { backgroundRGB != nil }

    /// The palette while an image's color is still being computed, or when there is no image: the
    /// app's own dark page and text colors.
    public static var placeholder: BleedPalette {
        BleedPalette(
            background: .backgroundMain,
            primaryText: .textMain,
            secondaryText: .textSecondary,
            bodyText: .textMain,
            secondaryTextStyle: BleedTextStyle(color: .textSecondary),
            tertiaryTextStyle: BleedTextStyle(color: .textTertiary),
            bodyTextStyle: BleedTextStyle(color: .textMain),
            controlSecondaryTextStyle: BleedTextStyle(color: .textSecondary),
            hairline: .rowSeparator,
            controlTint: .backgroundRow,
            controlLabel: .textMain,
            colorScheme: .dark,
            backgroundRGB: nil
        )
    }

    init(
        background: Color,
        primaryText: Color,
        secondaryText: Color,
        bodyText: Color,
        secondaryTextStyle: BleedTextStyle,
        tertiaryTextStyle: BleedTextStyle,
        bodyTextStyle: BleedTextStyle,
        controlSecondaryTextStyle: BleedTextStyle,
        hairline: Color,
        controlTint: Color,
        controlLabel: Color,
        colorScheme: ColorScheme,
        backgroundRGB: BleedRGB?
    ) {
        self.background = background
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.bodyText = bodyText
        self.secondaryTextStyle = secondaryTextStyle
        self.tertiaryTextStyle = tertiaryTextStyle
        self.bodyTextStyle = bodyTextStyle
        self.controlSecondaryTextStyle = controlSecondaryTextStyle
        self.hairline = hairline
        self.controlTint = controlTint
        self.controlLabel = controlLabel
        self.colorScheme = colorScheme
        self.backgroundRGB = backgroundRGB
    }

    /// Builds the palette from an extracted bleed color.
    init(base: BleedRGB, settings: BleedSettings = .default) {
        let background = Self.adjustedBackground(base, settings: settings)
        let text = BleedRGB.white
        let onBackground = Self.textStyles(text, on: background, settings: settings)

        // Controls: a lifted pill with a touch more chroma, unless that would drop the label
        // below 4.5:1, in which case the pill moves the other way.
        let tint = Self.controlTint(for: OKLab(background), text: text)
        // Text on a surface filled with that tint is solved against the tint, not the page.
        let onTint = Self.textStyles(text, on: tint, settings: settings)

        self.init(
            background: background.color,
            primaryText: text.color,
            secondaryText: onBackground.flatSecondary.color,
            bodyText: onBackground.flatBody.color,
            secondaryTextStyle: onBackground.secondary,
            tertiaryTextStyle: onBackground.tertiary,
            bodyTextStyle: onBackground.body,
            controlSecondaryTextStyle: onTint.secondary,
            hairline: text.color.opacity(0.18),
            controlTint: tint.color,
            controlLabel: text.color,
            colorScheme: .dark,
            backgroundRGB: background
        )
    }

    /// The text styles for `text` on `surface`: vibrant where it stays legible (3:1 for secondary
    /// and tertiary metadata, 4.5:1 for body paragraphs), else flat at the lowest opacity that does.
    private struct TextStyles {
        let secondary: BleedTextStyle
        let tertiary: BleedTextStyle
        let body: BleedTextStyle
        let flatSecondary: BleedTextStyle
        let flatBody: BleedTextStyle
    }

    private static func textStyles(_ text: BleedRGB, on surface: BleedRGB, settings: BleedSettings) -> TextStyles {
        let secondaryOpacity = flatOpacity(text, on: surface, from: secondaryOpacityFloor, minimumContrast: 4.5)
        let tertiaryOpacity = flatOpacity(text, on: surface, from: tertiaryOpacityFloor, minimumContrast: 3)
        let bodyOpacity = flatOpacity(text, on: surface, from: bodyOpacityFloor, step: 0.05, minimumContrast: 4.5)
        let flatSecondary = BleedTextStyle(color: text.color.opacity(secondaryOpacity))
        let flatTertiary = BleedTextStyle(color: text.color.opacity(tertiaryOpacity))
        let flatBody = BleedTextStyle(color: text.color.opacity(bodyOpacity))

        var vibrantSecondary: BleedTextStyle?
        var vibrantTertiary: BleedTextStyle?
        var vibrantBody: BleedTextStyle?
        if settings.vibrantText {
            let opacity = settings.vibrantOpacity
            vibrantSecondary = vibrantStyle(text, on: surface, opacities: [opacity], minimumContrast: 3)
            // Tertiary starts quieter than secondary and climbs back toward it until it reads.
            vibrantTertiary = vibrantStyle(
                text,
                on: surface,
                opacities: stride(from: opacity * vibrantTertiaryScale, to: opacity, by: 0.02) + [opacity],
                minimumContrast: 3
            )
            // Body copy starts a step above secondary and climbs until it reaches 4.5:1.
            vibrantBody = vibrantStyle(
                text,
                on: surface,
                opacities: stride(from: min(opacity + vibrantBodyLift, 1), through: 1, by: 0.02),
                minimumContrast: 4.5
            )
        }
        return TextStyles(
            secondary: vibrantSecondary ?? flatSecondary,
            tertiary: vibrantTertiary ?? flatTertiary,
            body: vibrantBody ?? flatBody,
            flatSecondary: flatSecondary,
            flatBody: flatBody
        )
    }

    // MARK: - Text

    /// The lowest opacity from `floor` up (in `step`s) at which `text` keeps `minimumContrast`
    /// against `background` when composited normally; 1 if none does.
    private static func flatOpacity(
        _ text: BleedRGB,
        on background: BleedRGB,
        from floor: Double,
        step: Double = 0.02,
        minimumContrast: Double
    ) -> Double {
        stride(from: floor, through: 1.0, by: step).first { opacity in
            background.blended(with: text, opacity: opacity).contrast(with: background) >= minimumContrast
        } ?? 1
    }

    /// Vibrant `text` (plus-lighter) at the first of `opacities` whose effective color, the blend
    /// result on `background`, keeps `minimumContrast`; `nil` if none does.
    private static func vibrantStyle(
        _ text: BleedRGB,
        on background: BleedRGB,
        opacities: some Sequence<Double>,
        minimumContrast: Double
    ) -> BleedTextStyle? {
        let opacity = opacities.first { opacity in
            background.blended(with: text, opacity: opacity, mode: .plusLighter).contrast(with: background) >= minimumContrast
        }
        return opacity.map { BleedTextStyle(color: text.color.opacity($0), blendMode: .plusLighter) }
    }

    // MARK: - Adjustment

    private static func controlTint(for lab: OKLab, text: BleedRGB) -> BleedRGB {
        let step = 0.1
        for delta in [step, -step * 0.8] {
            let candidate = OKLab(
                lightness: min(max(lab.l + delta, 0), 1),
                chroma: lab.chroma * 1.15,
                hue: lab.hue
            ).gamutMappedRGB
            if candidate.contrast(with: text) >= 4.5 {
                return candidate
            }
        }
        return OKLab(lightness: lab.l, chroma: lab.chroma * 1.15, hue: lab.hue).gamutMappedRGB
    }

    /// The warm hue near-neutral images drift to, so a white plate or gray stone reads as a soft
    /// taupe instead of flat, muddy gray.
    private static let warmNeutralHue = 75.0
    /// The lowest opacity for flat secondary text.
    private static let secondaryOpacityFloor = 0.72
    /// The lowest opacity for flat tertiary text, held to 3:1 rather than 4.5:1.
    private static let tertiaryOpacityFloor = 0.5
    /// The lowest opacity for flat body paragraphs.
    private static let bodyOpacityFloor = 0.8
    /// Vibrant tertiary text starts at this fraction of the vibrant secondary opacity.
    private static let vibrantTertiaryScale = 0.75
    /// Vibrant body text starts this much above the vibrant secondary opacity.
    private static let vibrantBodyLift = 0.1
    private static let neutralChromaThreshold = 0.04

    /// The deep background for an extracted color: near-neutrals warmed, lightness pulled toward
    /// the dark target, chroma boosted under a lightness-aware ceiling.
    static func adjustedBackground(_ base: BleedRGB, settings: BleedSettings) -> BleedRGB {
        let lab = OKLab(base)
        var lightness = lab.l
        var chroma = lab.chroma
        var hue = lab.hue

        // 1. Near-neutral → gentle warm neutral, blended in a/b space so a cool gray drifts
        //    straight to warm instead of swinging through pink.
        if settings.neutralWarmth > 0, chroma < neutralChromaThreshold {
            let neutrality = 1 - chroma / neutralChromaThreshold // 1 = pure gray
            let amount = min(1, neutrality * settings.neutralWarmth)
            let warm = OKLab(lightness: lightness, chroma: 0.022 * settings.neutralWarmth, hue: warmNeutralHue)
            let a = lab.a + (warm.a - lab.a) * amount
            let b = lab.b + (warm.b - lab.b) * amount
            let blended = OKLab(l: lightness, a: a, b: b)
            chroma = blended.chroma
            hue = blended.hue
        }

        // 2. Lightness moves only part of the way to the target (`lightnessPull`): the bleed must
        //    continue the image tonally or the seam shows as a fog band.
        lightness += (settings.lightnessDark - lightness) * min(max(settings.lightnessPull, 0), 1)
        // 3. Guard rails: deep enough for white text and to hand off into the dark page.
        lightness = min(max(lightness, 0.12), 0.55)

        // 4. Saturation, with a loose lightness-aware ceiling so deep tones don't turn neon.
        chroma *= settings.saturation
        chroma = min(chroma, 0.06 + 0.4 * lightness)

        return OKLab(lightness: lightness, chroma: chroma, hue: hue).gamutMappedRGB
    }
}

extension BleedPalette {
    /// Secondary text on the bleed, vibrant when the palette keeps 3:1, else flat.
    public var secondaryStyle: AnyShapeStyle { secondaryTextStyle.shapeStyle }
    /// Quieter labels than secondary, such as a caption under a value; vibrant or flat, at least 3:1.
    public var tertiaryStyle: AnyShapeStyle { tertiaryTextStyle.shapeStyle }
    /// Paragraph text on the bleed; vibrant or flat, at least 4.5:1.
    public var bodyStyle: AnyShapeStyle { bodyTextStyle.shapeStyle }
    /// Secondary text drawn on a surface filled with `controlTint`, solved against the tint rather
    /// than the page; use it for any text on a tile or card.
    public var controlSecondaryStyle: AnyShapeStyle { controlSecondaryTextStyle.shapeStyle }
}

extension EnvironmentValues {
    /// The palette of the nearest `.bleedPalette(key:image:settings:)` ancestor.
    @Entry public var bleedPalette: BleedPalette = .placeholder
}
