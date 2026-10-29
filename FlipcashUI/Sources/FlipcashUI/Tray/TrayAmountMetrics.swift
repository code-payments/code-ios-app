//
//  TrayAmountMetrics.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The amount tray's sizes and gaps: the full-screen entry's, scaled to a tray.
@MainActor
enum TrayAmountMetrics {

    /// The amount's size; the full-screen entry's is 74.
    static let amountSize: CGFloat = 60
    /// The amount's line, in the full-screen entry's 90 : 74 proportion.
    static var amountHeight: CGFloat { (amountSize * 90 / 74).rounded(.up) }
    static let amountToCaption: CGFloat = 4
    static let captionSize: CGFloat = 16
    static let captionToKeypad: CGFloat = 24
    /// How far the keypad reaches into the tray's side padding; the padding's 24 runs it edge to edge.
    static let keypadSideBleed: CGFloat = 16
}
