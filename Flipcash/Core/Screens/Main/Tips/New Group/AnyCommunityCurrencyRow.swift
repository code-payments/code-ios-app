//
//  AnyCommunityCurrencyRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What a group's balance requirement is named when it counts any community currency rather than
/// one token.
enum AnyCommunityCurrency {
    static let name = "Any Community Currency"
}

/// The currency picker's "Any Community Currency" entry, the last item of its list. Laid out like
/// ``CurrencyBalanceRow`` so its icon and check sit on the same lines as the token rows'.
struct AnyCommunityCurrencyRow: View {

    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AllCurrenciesIcon(size: 24)

                Text(AnyCommunityCurrency.name)
                    .font(.appBarButton)
                    .foregroundStyle(Color.textMain)

                Spacer()

                RadioButton(isSelected: isSelected)
                    .accessibilityHidden(true)
                    .padding(.leading, 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("any-community-currency-row")
    }
}

/// The form's tappable currency row: the chosen token, or the any-currency glyph, and a chevron.
struct CommunityCurrencyRow<Icon: View>: View {

    let name: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 8) {
                    icon()
                    Text(name)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The coins glyph on a grey disc that stands in for a token's icon when a requirement counts any
/// community currency (node 10369:999).
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
