//
//  ConversionGraphic.swift
//  FlipcashUI
//

import SwiftUI

/// A coin face `ConversionGraphic` can show on either side of the arrow.
public enum ConversionCoin {
    /// The gold "Dollars" coin — Flipcash's own reserve currency.
    case dollars

    /// The USDC coin with the Solana badge on its bottom-trailing corner.
    case usdcOnSolana
}

/// The "converted 1:1" education art: two coins separated by an arrow.
///
/// Composed here rather than shipped as one flattened asset so the same art serves both
/// directions — Dollars → USDC when withdrawing, and the inverse when adding money from
/// another wallet.
public struct ConversionGraphic: View {

    private let from: ConversionCoin
    private let to: ConversionCoin

    public init(from: ConversionCoin, to: ConversionCoin) {
        self.from = from
        self.to = to
    }

    public var body: some View {
        HStack(spacing: 16) {
            coin(from)

            Image.system(.arrowRight)
                .foregroundStyle(Color.textSecondary)

            coin(to)
        }
    }

    @ViewBuilder
    private func coin(_ coin: ConversionCoin) -> some View {
        switch coin {
        case .dollars:
            Image.asset(.buyDollars)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)

        case .usdcOnSolana:
            // Badge is an overlay, so the coin still lays out as a flat 100pt square.
            BadgedIcon(
                icon: Image.asset(.buyUSDC),
                badge: Image.asset(.buySolana)
            )
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        ConversionGraphic(from: .dollars, to: .usdcOnSolana)
        ConversionGraphic(from: .usdcOnSolana, to: .dollars)
    }
}
