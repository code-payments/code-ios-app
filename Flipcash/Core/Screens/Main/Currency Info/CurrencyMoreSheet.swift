//
//  CurrencyMoreSheet.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The sheet Currency Info's More tile opens: Convert, Withdraw and (outside USDF) Deposit, as the
/// same cards the group Send/Request sheet uses. No title and no Dismiss, matching that sheet.
struct CurrencyMoreSheet: View {

    @Environment(\.dismiss) private var dismiss

    let name: String
    let rows: [CurrencyInfoActions.MoreRow]
    /// False dims Convert and stops it opening, as the Dollars tile did when there was nothing to convert into.
    var canConvert: Bool = true
    var isUSDF = false
    let onSelect: (CurrencyInfoActions.MoreRow) -> Void

    var body: some View {
        PartialSheet {
            VStack(spacing: 12) {
                ForEach(rows, id: \.self) { row in
                    let enabled = row != .convert || canConvert
                    ActionCardRow(
                        icon: icon(for: row),
                        title: CurrencyInfoActions.title(for: row),
                        subtitle: CurrencyInfoActions.subtitle(for: row, name: name, isUSDF: isUSDF),
                        identifier: "currency-more-\(CurrencyInfoActions.title(for: row).lowercased())"
                    ) {
                        dismiss()
                        onSelect(row)
                    }
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
    }

    private func icon(for row: CurrencyInfoActions.MoreRow) -> Image {
        switch row {
        case .convert:  Image("IconArrowBottomTop")
        case .withdraw: Image.asset(.withdraw)
        case .deposit:  Image.asset(.deposit)
        }
    }
}
