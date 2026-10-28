//
//  TrayAmountMetrics.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The amount tray's sizes and gaps: the full-screen entry's, scaled to a tray.
///
/// Every value is live in the tuner during the feel round and bakes back to a constant in Phase 2.
@MainActor
enum TrayAmountMetrics {

    /// The amount's size; the full-screen entry's is 74.
    static var amountSize: CGFloat { points("Amount size", 60, 40...74) } // LOCAL-TUNER
    /// The amount's line, in the full-screen entry's 90 : 74 proportion.
    static var amountHeight: CGFloat { (amountSize * 90 / 74).rounded(.up) }
    static var amountToCaption: CGFloat { points("Amount → caption", 4, 0...24) } // LOCAL-TUNER
    static var captionSize: CGFloat { points("Caption size", 16, 11...20) } // LOCAL-TUNER
    static var captionToKeypad: CGFloat { points("Caption → keypad", 24, 0...64) } // LOCAL-TUNER
    /// How far the keypad reaches into the tray's side padding; the padding's 24 runs it edge to edge.
    static var keypadSideBleed: CGFloat { points("Keypad side bleed", 16, 0...24) } // LOCAL-TUNER

    private static func points(_ name: String, _ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        Tuner.shared.value("Tray Amount/\(name)", default: value, in: range, unit: .points) // LOCAL-TUNER
    }
}
