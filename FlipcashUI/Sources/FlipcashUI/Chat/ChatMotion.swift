//
//  ChatMotion.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// The transcript's motion language — spring parameters ported from the design prototype, where
/// they were tuned as SwiftUI `.spring(duration:bounce:)` values. `UIView.animate(springDuration:
/// bounce:)` and `CASpringAnimation(perceptualDuration:bounce:)` take the same pair directly, so
/// the numbers carry over verbatim.
enum ChatMotion {

    struct Spring {
        let duration: TimeInterval
        let bounce: CGFloat
    }

    /// A new bubble (or the typing indicator) entering, and the batch transaction it rides in.
    static let insertion = Spring(duration: 0.23, bounce: 0.27)
    /// Scale an entering row grows in from, anchored at its sender's edge.
    static let insertionScale: CGFloat = 0.95
    /// The animated scroll that brings the newest message into view.
    static let scroll = Spring(duration: 0.30, bounce: 0.12)
    /// A receipt line ("Delivered") revealing under a bubble.
    static let receiptReveal = Spring(duration: 0.40, bounce: 0.12)
    /// Scale the receipt line grows in from.
    static let receiptRevealScale: CGFloat = 0.95
    /// The Delivered → Read label swap.
    static let receiptSwapDuration: TimeInterval = 0.26
    /// A bubble's corner radius morph when its grouping changes.
    static let cornerMorph = Spring(duration: 0.45, bounce: 0.32)
}
#endif
