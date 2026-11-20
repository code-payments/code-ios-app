//
//  CollectionCurrencyPickerSheet.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// "Select Payment Currency": the pay sheet's picker when paying a collection.
/// Rows show each currency's icon and name with a radio for the selection, and
/// no balances. The list is the same one the shipped picker gets.
struct CollectionCurrencyPickerSheet: View {
    let options: [ExchangedBalance]
    let selectedMint: PublicKey
    let onSelect: (PublicKey) -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                // Sizes from frame 6.3 (node 13996:243). The title sits 26 points above the first
                // row's 54-point body, half the 22-point row gap being the row's own padding.
                Text("Select Payment Currency")
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .padding(.bottom, 26 - Self.rowGap / 2)

                // A List so a drag scrolls and never fires a row on release.
                List {
                    ForEach(options) { balance in
                        Button {
                            onSelect(balance.stored.mint)
                        } label: {
                            row(for: balance)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            balance.stored.mint == .usdf
                                ? "currency-picker-row-usdf"
                                : "currency-picker-row"
                        )
                        .accessibilityAddTraits(balance.stored.mint == selectedMint ? .isSelected : [])
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The space between two rows' 54-point bodies, split as padding inside each row so the whole
    /// pitch takes the tap.
    private static let rowGap: CGFloat = 22

    private func row(for balance: ExchangedBalance) -> some View {
        HStack(spacing: 12) {
            TokenIcon(url: balance.stored.imageURL, monogramID: balance.stored.mint.base58, size: 34)
            Text(balance.stored.name)
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            PaymentCurrencyRadio(isSelected: balance.stored.mint == selectedMint)
                .padding(.trailing, 12)
        }
        .frame(minHeight: 54)
        .padding(.vertical, Self.rowGap / 2)
        .contentShape(Rectangle())
    }
}

/// A ring, filled with a 12-point dot when selected.
private struct PaymentCurrencyRadio: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.textMain : Color.textSecondary, lineWidth: 2)
            if isSelected {
                Circle()
                    .fill(Color.textMain)
                    .padding(6)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
