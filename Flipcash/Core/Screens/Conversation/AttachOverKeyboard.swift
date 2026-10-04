//
//  AttachOverKeyboard.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Observation
import FlipcashCore

/// How `+` puts the attach panel up while the keyboard is up.
nonisolated enum AttachOverlayMode: String, Equatable {
    /// Over the live keys, in the keyboard's own window, which ``KeyboardOverlayHost`` finds.
    case keyboardWindow
    /// Over a plain keyboard-coloured backdrop swapped in as the field's input view, in the window
    /// that input view lands in.
    case inputView
    /// The keyboard goes down first and the panel rides the bar down with it.
    case dismissKeyboard

    /// The least keyboard height that counts as a software keyboard. A hardware keyboard leaves only
    /// the shortcut bar, which is no keyboard to draw over.
    static let minimumKeyboardHeight: CGFloat = 150

    /// Picks the mode for a keyboard `keyboardHeight` points tall, given whether its window was found
    /// and whether the field can take a replacement input view.
    static func select(keyboardHeight: CGFloat, hasKeyboardWindow: Bool, canReplaceInputView: Bool) -> Self {
        guard keyboardHeight >= minimumKeyboardHeight else { return .dismissKeyboard }
        if hasKeyboardWindow { return .keyboardWindow }
        if canReplaceInputView { return .inputView }
        return .dismissKeyboard
    }

    /// Whether the panel and its cards are drawn over the keyboard rather than in the bar.
    var drawsOverKeyboard: Bool {
        switch self {
        case .keyboardWindow, .inputView:   true
        case .dismissKeyboard:              false
        }
    }
}

/// The attach mode chosen for one tap of `+`, with the keyboard window when that is where it goes.
@MainActor
struct AttachOverlayPlan {
    let mode: AttachOverlayMode
    let keyboardWindow: UIWindow?

    /// Plans the mode with `locator` asked for the keyboard's window, which it may not find.
    init(locator: any KeyboardWindowLocating, keyboardHeight: CGFloat, canReplaceInputView: Bool) {
        // Asked only for a keyboard tall enough to draw over, so the private lookup runs no more
        // than it has to.
        let window = keyboardHeight >= AttachOverlayMode.minimumKeyboardHeight ? locator.keyboardWindow() : nil
        mode = AttachOverlayMode.select(
            keyboardHeight: keyboardHeight,
            hasKeyboardWindow: window != nil,
            canReplaceInputView: canReplaceInputView
        )
        keyboardWindow = mode == .keyboardWindow ? window : nil
    }
}

/// Whether the attach panel and its cards are drawn over the keyboard, and what that drawing needs
/// from the bar underneath it: where `+` and the field are, and the chip a photo lands as.
///
/// The bar lives in the app's window and the overlay in the keyboard's, so they can't share a
/// `matchedGeometryEffect` namespace. The card shrinks onto a stand-in at the landing chip's frame
/// instead, which the bar measures and hands over here.
@MainActor
@Observable
final class AttachOverKeyboard {

    /// Whether the panel and cards are drawn over the keyboard rather than in the bar.
    private(set) var isActive = false

    /// The menu rows the panel showed as it opened.
    private(set) var items: [AttachMenuItem] = []

    /// `+`'s frame in window coordinates, as last laid out.
    var plusFrame: CGRect = .zero

    /// How far left of the composer field the bar's row starts: `$`'s width and gap while it shows,
    /// else zero. The menu opens out to there, so it covers the row it opens from.
    var menuLeadingReach: CGFloat = 0

    /// Whether the photo card opens the full library as it next mounts in the bar. Set when All
    /// Photos hands the card over to the keyboard-down flow, whose sheet the keyboard would cover.
    var opensLibraryInBar = false

    /// Starts drawing over the keyboard, with `items` as the panel's rows.
    func activate(items: [AttachMenuItem]) {
        self.items = items
        isActive = true
    }

    /// Hands drawing back to the bar.
    func deactivate() {
        isActive = false
    }
}

nonisolated enum AttachOverlayLayout {

    /// The margin between a card and the screen's sides and bottom: the bar's keyboard-up edge inset.
    static let cardInset: CGFloat = 12

    /// The panel's frame for a panel `size` big: its leading edge on the composer field's, which is
    /// the field's padding out from `+`'s, and centred on `+`'s
    /// bottom, the composer's bottom edge. It straddles that edge, as ChatGPT's does, so its lower
    /// half lies over the keys that blur through it and its upper half over the field.
    static func panelFrame(plusFrame: CGRect, size: CGSize) -> CGRect {
        // Centred on the field's bottom edge, a short menu tops out just under the field's top and
        // leaves its corner showing; lift it to clear the top by `fieldTopOverhang`.
        let fieldTop = plusFrame.maxY + BarMetrics.fieldPadding - BarMetrics.contentHeight
        let y = min(plusFrame.maxY - size.height / 2, fieldTop - fieldTopOverhang)
        return CGRect(x: plusFrame.minX - BarMetrics.fieldPadding, y: y, width: size.width, height: size.height)
    }

    /// How far the open menu reaches above the composer field's top edge.
    static let fieldTopOverhang: CGFloat = 8

    /// The point in a panel `size` big that `+`'s centre sits on, for the panel to grow out of and
    /// collapse back into.
    static func panelAnchor(plusFrame: CGRect, size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .leading }
        let frame = panelFrame(plusFrame: plusFrame, size: size)
        return UnitPoint(
            x: min(1, max(0, (plusFrame.midX - frame.minX) / size.width)),
            y: min(1, max(0, (plusFrame.midY - frame.minY) / size.height))
        )
    }

    /// The card's frame in a window `bounds` big: `height` tall, standing on the screen's bottom
    /// over the keyboard.
    static func cardFrame(in bounds: CGRect, height: CGFloat) -> CGRect {
        let width = max(0, bounds.width - cardInset * 2)
        let height = min(height, max(0, bounds.height - cardInset))
        return CGRect(x: bounds.minX + cardInset, y: bounds.maxY - cardInset - height, width: width, height: height)
    }
}
