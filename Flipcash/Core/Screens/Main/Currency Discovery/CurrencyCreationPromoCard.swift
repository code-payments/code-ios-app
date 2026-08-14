//
//  CurrencyCreationPromoCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyCreationPromoCard: View {
    /// The card's background treatment. `.solid` is the inline list row (legacy
    /// UI); `.glass` is the Liquid Glass surface used when the card floats pinned
    /// to the bottom in the new UI, letting the list blur through behind it.
    enum Surface {
        case solid
        case glass
    }

    var surface: Surface = .solid
    let action: () -> Void

    private let cornerRadius: CGFloat = 16

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Create Your Own Currency")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Image.system(.arrowRight)
                        .foregroundStyle(Color.textMain)
                }
                Text("Create a currency in minutes and\nimmediately use it as cash")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                Image(.CurrencyDiscovery.bills)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
            }
            .modifier(SurfaceBackground(surface: surface, cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discover-create-currency-card")
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

/// Paints the promo card's background: an opaque row fill for `.solid`, the app's
/// Liquid Glass surface for `.glass`. Both clip the bill artwork to the corners.
private struct SurfaceBackground: ViewModifier {
    let surface: CurrencyCreationPromoCard.Surface
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        switch surface {
        case .solid:
            content
                .background(Color.backgroundRow)
                .compositingGroup()
                .clipShape(.rect(cornerRadius: cornerRadius))
        case .glass:
            // Liquid Glass, tinted a touch lighter to match the Figma surface
            // (~white @ 10% over the dark list) rather than the dimmer default.
            if #available(iOS 26, *) {
                content
                    .clipShape(.rect(cornerRadius: cornerRadius))
                    .glassEffect(
                        .regular.tint(.white.opacity(0.05)).interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                // No Liquid Glass below iOS 26 — fall back to an opaque card at
                // the same surface tone so the list can't show through it.
                content
                    .background {
                        ZStack {
                            Color.backgroundMain
                            Color.white.opacity(0.10)
                        }
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius))
            }
        }
    }
}
