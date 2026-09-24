//
//  AllCurrenciesCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The currency picker's "All Currencies" choice for a group's balance requirement, stating the
/// user's total against the amount picked (node 10370:997).
struct AllCurrenciesCard: View {

    let isSelected: Bool
    /// Every holding added together, in USD — the figure the requirement is weighed against.
    let total: FiatAmount
    /// The amount picked on the form, or nil while none is.
    let requirement: FiatAmount?
    let meetsRequirement: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AllCurrenciesIcon(size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All Currencies")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)

                    Text(subtitle)
                        .font(.default(size: 13, weight: .medium))
                        .foregroundStyle(meetsRequirement ? Color.textMain.opacity(0.5) : Color.textError)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CheckView(active: isSelected)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(Color.backgroundRow, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.5 : 0.15))
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        // Margin plus padding matches the currency rows' 20pt inset, so the icon and check sit on
        // the same lines as the rows' icons and checks.
        .padding(.horizontal, 8)
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("all-currencies-card")
    }

    private var subtitle: String {
        // Rounded before it is shown, because the gate compares the rounded figure.
        let held = "You have \(total.roundedToSmallestUnit().formatted()) total"
        guard let requirement else { return held }
        let verdict = meetsRequirement ? "meets" : "need"
        return "\(held) · \(verdict) \(requirement.formattedDroppingZeroFraction())"
    }
}

/// The coins glyph on a grey disc that stands in for a token's icon when a requirement counts every
/// holding (node 10369:999).
struct AllCurrenciesIcon: View {

    let size: CGFloat

    var body: some View {
        Circle()
            // White at 15% over the sheet's charcoal is the design's #3B3B3D.
            .fill(Color.white.opacity(0.15))
            .frame(width: size, height: size)
            .overlay {
                Image.asset(.coins)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.625, height: size * 0.625)
                    .foregroundStyle(Color.textMain)
            }
    }
}
