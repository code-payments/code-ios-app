//
//  ChatMotion.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

/// The transcript's motion language — the design prototype's spring values, with Reduce Motion
/// collapsing bounces and scales at the token so consuming sites need no branching.
enum ChatMotion {

    static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// A new bubble (or the typing indicator) entering, and the batch transaction it rides in.
    static var insertion: Spring { Spring(duration: 0.23, bounce: isReduced ? 0 : 0.27) }
    /// Scale an entering row grows in from, anchored at its sender's edge.
    static var insertionScale: CGFloat { isReduced ? 1 : 0.95 }
    /// The animated scroll that brings the newest message into view.
    static var scroll: Spring { Spring(duration: 0.30, bounce: isReduced ? 0 : 0.12) }
    /// A receipt line ("Delivered") revealing under a bubble.
    static var receiptReveal: Spring { Spring(duration: 0.40, bounce: isReduced ? 0 : 0.12) }
    /// Scale the receipt line grows in from.
    static var receiptRevealScale: CGFloat { isReduced ? 1 : 0.95 }
    /// The Delivered → Read label swap.
    static let receiptSwapDuration: TimeInterval = 0.26
    /// A bubble's corner radius morph when its grouping changes. Skipped, not softened, under
    /// Reduce Motion — see `BubbleBackgroundView.apply`.
    static let cornerMorph = Spring(duration: 0.45, bounce: 0.32)
}
#endif
