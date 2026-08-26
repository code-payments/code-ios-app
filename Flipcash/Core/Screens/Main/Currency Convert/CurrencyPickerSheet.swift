//
//  CurrencyPickerSheet.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// "Select Currency" bottom sheet listing balances to pick from — the Convert
/// destination (Dollars + held tokens) or the Get payment source. Picking one
/// calls `onSelect` with its mint.
struct CurrencyPickerSheet: View {
    let options: [ExchangedBalance]
    let selectedMint: PublicKey
    let onSelect: (PublicKey) -> Void
    var title: String = "Select Currency"

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                // A List (not a ScrollView of Buttons) so rows get native
                // scroll-vs-tap handling — a drag scrolls and never fires a row
                // on release — and the system soft scroll edge fades the top and
                // bottom without a hard clip line.
                List {
                    ForEach(options) { balance in
                        Button {
                            onSelect(balance.stored.mint)
                        } label: {
                            row(for: balance)
                        }
                        .buttonStyle(.plain)
                        // Dollars carries its own identifier so a test can pick
                        // it, or any token, without depending on where balances
                        // sort.
                        .accessibilityIdentifier(
                            balance.stored.mint == .usdf
                                ? "currency-picker-row-usdf"
                                : "currency-picker-row"
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // Fade the top and bottom scroll edges into the sheet background
                // so rows soften out rather than clipping against a hard line.
                .overlay(alignment: .top) { edgeFade(.top) }
                .overlay(alignment: .bottom) { edgeFade(.bottom) }
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

            if balance.stored.mint == selectedMint {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textMain)
            }

            Text(balance.exchangedFiat.nativeAmount.formatted())
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// A background-coloured gradient band that fades the list content into the
    /// sheet at the given edge. Non-interactive so it never blocks a row tap.
    private func edgeFade(_ edge: VerticalEdge) -> some View {
        LinearGradient(
            colors: edge == .top ? [.backgroundMain, .clear] : [.clear, .backgroundMain],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 28)
        .allowsHitTesting(false)
    }
}
