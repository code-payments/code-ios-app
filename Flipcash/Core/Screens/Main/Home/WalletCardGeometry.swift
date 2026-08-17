//
//  WalletCardGeometry.swift
//  Flipcash
//

import CoreGraphics

/// Where an opened token card sits, shared by the wallet (which animates the
/// card there) and the currency info screen (whose hero card must land on the
/// same spot for the hand-off between them to be invisible).
///
/// Taken from the currency info spec (Figma 9121:14267): 44pt chrome at y=66,
/// card at y=134.5.
enum WalletCardGeometry {
    /// Distance from the top of the scroll container to the opened card.
    static let openCardTopInset: CGFloat = 72
    /// The card's height in both places.
    static let cardHeight: CGFloat = 224
}
