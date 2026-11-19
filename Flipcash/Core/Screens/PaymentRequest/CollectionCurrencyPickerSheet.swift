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
                Text("Select Payment Currency")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 12)

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

    private func row(for balance: ExchangedBalance) -> some View {
        HStack(spacing: 12) {
            TokenIconWithName(
                url: balance.stored.imageURL,
                monogramID: balance.stored.mint.base58,
                name: balance.stored.name,
                iconSize: 32
            )
            Spacer()
            PaymentCurrencyRadio(isSelected: balance.stored.mint == selectedMint)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// A ring, filled with a dot when selected.
private struct PaymentCurrencyRadio: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.textMain : Color.textSecondary, lineWidth: 2)
            if isSelected {
                Circle()
                    .fill(Color.textMain)
                    .padding(5)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
