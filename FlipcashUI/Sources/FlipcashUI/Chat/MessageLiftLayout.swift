//
//  MessageLiftLayout.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics

/// Where a lifted bubble, its reaction strip and its action menu go on screen: the strip always
/// above the bubble, the menu always below it, all inside the safe area. The bubble keeps its row's
/// position when that fits, moves the least distance that makes it fit otherwise, and scales down
/// toward its own side when even the whole screen is too short for it.
nonisolated struct MessageLiftLayout: Equatable {

    /// The lifted bubble, in the same space as the inputs.
    let bubble: CGRect
    /// The top of the strip, or `nil` when the lift has no strip.
    let stripTop: CGFloat?
    /// The menu platter, or `nil` when the lift has no menu.
    let menu: CGRect?

    /// The space between the bubble and the menu below it.
    static let menuGap: CGFloat = 8
    /// The least room kept between the lift and the safe area's top and bottom edges.
    static let edgeMargin: CGFloat = 16
    /// The least room kept between the menu and the screen's sides.
    static let sideMargin: CGFloat = 16
    /// The smallest a bubble is scaled to, so an extreme message still reads as the one pressed.
    static let minimumScale: CGFloat = 0.3

    /// Lays out a lift of `bubble` inside `bounds` less `safeArea`.
    /// - Parameters:
    ///   - stripHeight: the strip's height, or `nil` for no strip.
    ///   - menuSize: the menu's size, or `nil` for no menu.
    init(
        bubble home: CGRect,
        bounds: CGRect,
        safeArea: (top: CGFloat, bottom: CGFloat),
        stripHeight: CGFloat?,
        stripGap: CGFloat,
        menuSize: CGSize?
    ) {
        let top = bounds.minY + safeArea.top + Self.edgeMargin
        let bottom = bounds.maxY - safeArea.bottom - Self.edgeMargin
        let above = stripHeight.map { $0 + stripGap } ?? 0
        let below = menuSize.map { $0.height + Self.menuGap } ?? 0

        let room = bottom - top - above - below
        let scale = home.height > room
            ? max(Self.minimumScale, room / home.height)
            : 1
        let size = CGSize(width: home.width * scale, height: home.height * scale)

        let hugsTrailing = home.midX > bounds.midX
        let x = hugsTrailing ? home.maxX - size.width : home.minX
        let highest = top + above
        let lowest = max(highest, bottom - below - size.height)
        let y = min(max(home.minY, highest), lowest)
        let lifted = CGRect(origin: CGPoint(x: x, y: y), size: size)

        bubble = lifted
        stripTop = stripHeight.map { lifted.minY - stripGap - $0 }
        menu = menuSize.map { menu in
            let preferred = hugsTrailing ? lifted.maxX - menu.width : lifted.minX
            let minX = bounds.minX + Self.sideMargin
            let maxX = bounds.maxX - Self.sideMargin - menu.width
            return CGRect(
                x: min(max(preferred, minX), max(minX, maxX)),
                y: lifted.maxY + Self.menuGap,
                width: menu.width,
                height: menu.height
            )
        }
    }
}
