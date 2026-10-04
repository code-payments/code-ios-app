//
//  AttachSurface.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI

/// What the attach surface is showing.
nonisolated enum AttachSurfacePhase: Equatable {
    /// Shrunk into `+` and faded out: on its way in or out.
    case collapsed
    /// The menu's rows.
    case menu
    /// The camera or photo card.
    case card(AttachCard.Content)
    /// Shrinking onto the chip a capture or added photo was staged as.
    case landing

    /// The phase for a panel that `isMenuOpen`, the card `card` up if any, and whether a landing is
    /// under way. A card wins over the panel, which closes in the transaction the card opens in.
    init(isMenuOpen: Bool, card: AttachCard.Content?, isLanding: Bool) {
        if let card {
            self = .card(card)
        } else if isMenuOpen {
            self = .menu
        } else if isLanding {
            self = .landing
        } else {
            self = .collapsed
        }
    }

    /// Whether the menu's rows are shown.
    var showsRows: Bool {
        switch self {
        case .menu:                             true
        case .collapsed, .card, .landing:       false
        }
    }

    /// The card whose content is shown, if any.
    var shownCard: AttachCard.Content? {
        switch self {
        case .card(let content):                content
        case .collapsed, .menu, .landing:       nil
        }
    }
}

/// Where the menu stands against `+`.
nonisolated enum AttachMenuPlacement: Equatable {
    /// On the composer's bottom edge, growing up out of `+`: in the bar, with the keyboard down.
    case standsOnPlus
    /// Centred on the composer's bottom edge, over the keys: drawn over the keyboard.
    case straddlesPlus
}

/// The surface's frame and corner radius, which spring together.
nonisolated struct AttachSurfaceShape: Equatable {
    var rect: CGRect
    var cornerRadius: CGFloat
}

/// Where the attach surface stands in each phase, in its host's coordinates.
enum AttachSurfaceLayout {

    /// Matches the composer field's corner, so the menu reads as part of it.
    static let menuCornerRadius: CGFloat = BarMetrics.fieldCornerRadius
    /// `+`'s flat fill on the composer field, which the surface turns into as it reaches `+`.
    static let plusFill = Color.white.opacity(0.10)
    /// How far past `+`'s size the surface has fully turned from `+`'s fill into the panel's glass.
    static let plusBlendDistance: CGFloat = 40
    static let cardCornerRadius: CGFloat = 24
    /// A staged chip's radius, which a landing ends on.
    static let chipCornerRadius: CGFloat = 10
    /// The menu's width: room for an icon and a short label, well short of the send button.
    static let menuWidth: CGFloat = 220
    /// A menu row's height, sized to the system's own attachment menus.
    static let menuRowHeight: CGFloat = 62
    static let menuVerticalPadding: CGFloat = 10
    /// The rows' blur and scale while hidden, which they sharpen and grow out of as the menu opens.
    static let rowsBloomBlur: CGFloat = 8
    static let rowsBloomScale: CGFloat = 0.85

    /// The menu's size before its rows are measured.
    static func estimatedMenuSize(rowCount: Int) -> CGSize {
        CGSize(width: menuWidth, height: CGFloat(rowCount) * menuRowHeight + menuVerticalPadding * 2)
    }

    /// The menu's frame for a menu `size` big, placed against `plus` by `placement`. Either way its
    /// leading edge is the composer field's, ``BarMetrics/fieldPadding`` out from `+`'s, moved out a
    /// further `leadingReach` at the same width; standing on `+`, its bottom edge is the field's too.
    static func menuRect(plus: CGRect, size: CGSize, placement: AttachMenuPlacement, leadingReach: CGFloat = 0) -> CGRect {
        let rect = fieldAlignedMenuRect(plus: plus, size: size, placement: placement)
        return CGRect(x: rect.minX - leadingReach, y: rect.minY, width: rect.width, height: rect.height)
    }

    private static func fieldAlignedMenuRect(plus: CGRect, size: CGSize, placement: AttachMenuPlacement) -> CGRect {
        switch placement {
        case .standsOnPlus:
            CGRect(x: plus.minX - BarMetrics.fieldPadding, y: plus.maxY + BarMetrics.fieldPadding - size.height, width: size.width, height: size.height)
        case .straddlesPlus:
            AttachOverlayLayout.panelFrame(plusFrame: plus, size: size)
        }
    }

    /// The card's frame in the bar, in the composer row's coordinates: standing on the row's bottom
    /// edge, `height` tall, and `outset` wider than the row on each side.
    static func barCardRect(row: CGSize, outset: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: -outset, y: row.height - height, width: row.width + outset * 2, height: height)
    }

    /// Returns the radius of the surface collapsed onto `plus`, which is a circle: half its height.
    static func collapsedCornerRadius(plus: CGRect) -> CGFloat {
        plus.height / 2
    }

    /// The surface's shape in `phase`. A landing whose chip hasn't been laid out yet holds the card's.
    static func shape(for phase: AttachSurfacePhase, plus: CGRect, menu: CGRect, card: CGRect, landing: CGRect?) -> AttachSurfaceShape {
        switch phase {
        case .collapsed:
            AttachSurfaceShape(rect: plus, cornerRadius: collapsedCornerRadius(plus: plus))
        case .menu:
            AttachSurfaceShape(rect: menu, cornerRadius: menuCornerRadius)
        case .card:
            AttachSurfaceShape(rect: card, cornerRadius: cardCornerRadius)
        case .landing:
            if let landing {
                AttachSurfaceShape(rect: landing, cornerRadius: chipCornerRadius)
            } else {
                AttachSurfaceShape(rect: card, cornerRadius: cardCornerRadius)
            }
        }
    }

    /// The regions that take touches in `phase`: the menu while it shows, the card while it is up.
    static func regions(for phase: AttachSurfacePhase, menu: CGRect, card: CGRect) -> [AttachOverlayRegion: CGRect] {
        switch phase {
        case .menu:                     [.panel: menu]
        case .card:                     [.card: card]
        case .collapsed, .landing:      [:]
        }
    }
}

/// The attach flow's one surface: a single glass shape that grows out of `+` into the menu, springs
/// between the menu and the camera or photo card, and shrinks onto the chip a photo is staged as.
///
/// Only its frame and corner radius move. Its content is laid out at its final size from the moment
/// the surface appears — the camera's viewfinder and the inline photo picker at the card's, the rows
/// at the menu's — and cross-fades inside the clip: the leaving side out early and fast, the arriving
/// side in late. Drawn in the bar with the keyboard down, and over the keyboard with it up; the host
/// passes `+`'s frame, the card's, and the landing chip's in its own coordinates.
struct AttachSurface: View {

    let model: ConversationBarModel
    let items: [AttachMenuItem]
    let plus: CGRect
    let card: CGRect
    let landing: CGRect?
    let menuPlacement: AttachMenuPlacement
    let selectionLimit: Int
    let actions: AttachOverlayActions
    /// Whether the photo card opens the full picker as it mounts, for one All Photos was handed to.
    var opensLibraryOnAppear = false
    /// Receives the regions that take touches as they change, and none once the surface is gone.
    var report: (AttachOverlayRegion, CGRect?) -> Void = { _, _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off for the first render, so the surface starts in `+` and grows out of it.
    @State private var appeared = false
    @State private var menuSize: CGSize?

    var body: some View {
        let motion = AttachMotion(reduceMotion: reduceMotion)
        let phase = model.attachSurfacePhase
        let menu = AttachSurfaceLayout.menuRect(
            plus: plus,
            size: menuSize ?? AttachSurfaceLayout.estimatedMenuSize(rowCount: items.count),
            placement: menuPlacement,
            leadingReach: model.overKeyboard.menuLeadingReach
        )
        let shape = AttachSurfaceLayout.shape(for: appeared ? phase : .collapsed, plus: plus, menu: menu, card: card, landing: landing)
        // Morphing, the surface is `+` at either end and stays opaque; a cross-fade fades it instead.
        let isVisible = motion.animatesGeometry || (appeared && phase != .collapsed)
        let showsPlusGlyph = !appeared || phase == .collapsed
        AttachSurfaceFrame(shape: shape, plus: plus, blendsIntoPlus: phase != .landing) { rect in
            ZStack(alignment: .topLeading) {
                plusGlyph
                    .offset(x: plus.minX - rect.minX, y: plus.minY - rect.minY)
                    .attachLayer(isShown: showsPlusGlyph)
                cardLayer(phase: phase)
                    .frame(width: card.width, height: card.height)
                    .offset(x: card.minX - rect.minX, y: card.minY - rect.minY)
                // From the hand-off on, filling the surface at every step: the viewfinder holds the
                // capture, and it collapses into the chip rather than an empty surface flying there.
                if let image = model.attachCard.landingImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: rect.width, height: rect.height)
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.identity)
                }
                rows(phase: phase, menu: menu, motion: motion)
                    .frame(width: menu.width, height: menu.height, alignment: .topLeading)
                    .offset(x: menu.minX - rect.minX, y: menu.minY - rect.minY)
            }
        }
        // Under Reduce Motion the shape jumps; only the content and the surface's own opacity fade.
        .transaction(value: shape) { transaction in
            if !motion.animatesGeometry {
                transaction.animation = nil
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(ChatMotion.attachPanel.animation) { appeared = true }
        }
        .onChange(of: AttachSurfaceLayout.regions(for: phase, menu: menu, card: card), initial: true) { _, regions in
            report(.panel, regions[.panel])
            report(.card, regions[.card])
        }
        .onDisappear {
            report(.panel, nil)
            report(.card, nil)
        }
    }

    // MARK: - Content -

    /// `+`'s glyph where `+` stands, so the surface reads as `+` itself as it grows and collapses.
    private var plusGlyph: some View {
        Image(systemName: SystemSymbol.plus.rawValue)
            .font(.default(size: 17, weight: .semibold))
            .foregroundStyle(Color.textMain)
            .frame(width: plus.width, height: plus.height)
            .accessibilityHidden(true)
    }

    /// The rows sharpen out of a blur and grow from `+` as the surface opens, and go back into it as
    /// it closes, so they read as poured out of `+` rather than faded over it.
    private func rows(phase: AttachSurfacePhase, menu: CGRect, motion: AttachMotion) -> some View {
        let panel = model.attachPanel
        let shown = phase.showsRows
        let blooms = motion.animatesGeometry
        let anchor = UnitPoint(
            x: menu.width > 0 ? (plus.midX - menu.minX) / menu.width : 0,
            y: menu.height > 0 ? (plus.midY - menu.minY) / menu.height : 1
        )
        return AttachMenuRows(items: items, onSelect: { item in
            panel.select(item, warmUp: model.attachWarmUp, onCash: actions.onCash, onCamera: actions.onCamera, onPhotos: actions.onPhotos)
        }) {
            panel.animate { $0.dismiss() }
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { menuSize = $0 }
        .animation(ChatMotion.attachPanel.animation) {
            $0.blur(radius: shown || !blooms ? 0 : AttachSurfaceLayout.rowsBloomBlur)
                .scaleEffect(shown || !blooms ? 1 : AttachSurfaceLayout.rowsBloomScale, anchor: anchor)
        }
        .attachLayer(isShown: shown)
    }

    /// The camera and the photo picker, each mounted from the surface's first frame at the card's
    /// size, so neither is laid out again as the surface grows into it. The camera only once access
    /// is granted: mounted earlier, it would ask while the menu is up.
    private func cardLayer(phase: AttachSurfacePhase) -> some View {
        let shown = phase.shownCard
        let mountsCamera = items.contains(.camera) && (model.attachWarmUp.cameraIsAuthorized || shown == .camera)
        return ZStack {
            if mountsCamera {
                ChatCameraSheet(camera: model.attachWarmUp.camera, onCapture: actions.onCameraCapture, onCancel: actions.onCameraCancel)
                    .attachLayer(isShown: shown == .camera)
            }
            if items.contains(.photos) {
                ChatPhotosCard(
                    pick: model.photosPick,
                    selectionLimit: selectionLimit,
                    onAdd: actions.onPhotosAdd,
                    onBack: actions.onPhotosBack,
                    onAllPhotos: actions.onAllPhotos,
                    opensLibraryOnAppear: opensLibraryOnAppear
                )
                .onAppear { model.attachWarmUp.pickerDidMount() }
                .onDisappear { model.attachWarmUp.pickerDidUnmount() }
                .attachLayer(isShown: shown == .photos)
            }
        }
    }
}

private extension View {

    /// Shows this layer of the surface's content, or keeps it mounted but hidden and out of reach:
    /// fading in late as the surface arrives at it, and out early as the surface leaves.
    func attachLayer(isShown: Bool) -> some View {
        animation(isShown ? ChatMotion.attachContentIn : ChatMotion.attachContentOut) {
            $0.opacity(isShown ? 1 : 0)
        }
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
    }
}

/// The surface's glass and clip at one frame and corner radius, which animate as one value so the
/// two never drift apart mid-spring. `content` is handed the frame of each animated step, to keep
/// its layers where they rest while the clip moves over them.
private struct AttachSurfaceFrame<Content: View>: View, Animatable {

    var shape: AttachSurfaceShape
    /// `+`'s frame, which the surface takes on the look of as it shrinks to `+`'s size.
    let plus: CGRect
    /// Whether the surface turns into `+`'s fill near `+`'s size; not while it lands on a chip.
    let blendsIntoPlus: Bool
    let content: (CGRect) -> Content

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(shape.rect.animatableData, shape.cornerRadius) }
        set {
            shape.rect.animatableData = newValue.first
            shape.cornerRadius = newValue.second
        }
    }

    var body: some View {
        let rect = shape.rect
        let clip = RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
        let glass = glassAmount(at: rect)
        ZStack(alignment: .topLeading) {
            clip
                .fill(AttachSurfaceLayout.plusFill)
                .frame(width: rect.width, height: rect.height)
                .opacity(1 - glass)
            Color.clear
                .frame(width: rect.width, height: rect.height)
                .panelGlassBackground(cornerRadius: shape.cornerRadius)
                .opacity(glass)
            content(rect)
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .clipShape(clip)
        .contentShape(clip)
        .offset(x: rect.minX, y: rect.minY)
    }

    /// How much of the panel's glass shows at `rect`, against `+`'s flat fill: none at `+`'s size,
    /// all of it once the surface is a few dozen points bigger, so the two meet without a colour jump.
    private func glassAmount(at rect: CGRect) -> CGFloat {
        guard blendsIntoPlus else { return 1 }
        let growth = max(rect.width - plus.width, rect.height - plus.height)
        return min(max(growth / AttachSurfaceLayout.plusBlendDistance, 0), 1)
    }
}
