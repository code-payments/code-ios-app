//
//  BadgedIcon.swift
//  FlipcashUI
//

import SwiftUI

/// Round/rounded-square icon with an optional small badge anchored to the
/// bottom-trailing corner. Used by buy/withdraw hero graphics where a base
/// asset (USDC, Phantom) gets paired with a network/state marker (Solana hex,
/// checkmark) without baking the badge into the parent SVG.
public struct BadgedIcon: View {

    private let icon: Image
    private let badge: Image?
    private let size: CGFloat
    private let badgeSize: CGFloat
    private let badgeOffset: CGSize

    public init(
        icon: Image,
        badge: Image? = nil,
        size: CGFloat = 80,
        badgeSize: CGFloat = 28,
        badgeOffset: CGSize = CGSize(width: 4, height: 4)
    ) {
        self.icon = icon
        self.badge = badge
        self.size = size
        self.badgeSize = badgeSize
        self.badgeOffset = badgeOffset
    }

    public var body: some View {
        icon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    badge
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: badgeSize, height: badgeSize)
                        .offset(x: badgeOffset.width, y: badgeOffset.height)
                }
            }
    }
}
