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
    private let size: CGFloat = 100
    private let badgeSize: CGFloat = 38
    private let badgeOffset: CGPoint = CGPoint(x: 8, y: 8)

    public init(
        icon: Image,
        badge: Image? = nil,
    ) {
        self.icon = icon
        self.badge = badge
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
                        .offset(x: badgeOffset.x, y: badgeOffset.y)
                }
            }
    }
}

#Preview {
    BadgedIcon(icon: Image.asset(.buyPhantom))

    BadgedIcon(
        icon: Image.asset(.buyUSDC),
        badge: Image.asset(.buySolana)
    )
}
