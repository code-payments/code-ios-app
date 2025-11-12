//
//  TransactionDetailsModal.swift
//  Code
//
//  Created by Dima Bart on 2025-05-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct TransactionDetailsModal: View {
    
    @Binding var isPresented: Bool
    
    let activity: Activity
    let cancelAction: (Activity.CashLinkMetadata) -> Void
    
    private let detailRows: [DetailRow]
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, activity: Activity, cancelAction: @escaping (Activity.CashLinkMetadata) -> Void) {
        self._isPresented = isPresented
        self.activity = activity
        self.cancelAction = cancelAction
        self.detailRows = [
            DetailRow(
                title: "ID",
                subtitle: activity.id.base58
            ),
            DetailRow(
                title: "Status",
                subtitle: activity.state.description
            ),
            DetailRow(
                title: "Date",
                subtitle: activity.date.formatted()
            ),
            DetailRow(
                title: "Exchange Rate",
                subtitle: activity.exchangedFiat.rate.fx.formatted()
            ),
            DetailRow(
                title: "Currency",
                subtitle: activity.exchangedFiat.converted.currencyCode.rawValue.uppercased()
            ),
            DetailRow(
                title: "USDC",
                subtitle: activity.exchangedFiat.underlying.formatted(showAllDecimals: true)
            ),
        ]
    }
    
    // MARK: - Body -
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 15) {
                Text(activity.title)
                    .font(.appTextLarge)
                AmountText(
                    flagStyle: activity.exchangedFiat.converted.currencyCode.flagStyle,
                    flagSize: .regular,
                    content: activity.exchangedFiat.converted.formatted(),
                    canScale: false
                )
                .font(.appDisplaySmall)
            }
            .foregroundStyle(Color.textMain)
            .padding(.bottom, 20)
            
            VStack(spacing: 20) {
                ForEach(detailRows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.title)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textSecondary)
                        Text(row.subtitle)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            if let cashLinkMetadata = activity.cancellableCashLinkMetadata {
                CodeButton(style: .filled, title: "Cancel Send") {
                    isPresented = false
                    Task {
                        cancelAction(cashLinkMetadata)
                    }
                }
                .padding(.top, 30)
            }
        }
        .padding(20)
    }
}

private struct DetailRow: Identifiable {
    var id: String {
        title
    }
    
    let title: String
    let subtitle: String
}
