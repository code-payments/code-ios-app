//
//  TransactionHistoryScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-10-31.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct TransactionHistoryScreen: View {
    
    @StateObject private var updateableActivities: Updateable<[Activity]>
    
    @State private var dialogItem: DialogItem?
    
    @State private var selectedActivity: Activity?
    
    private var activities: [Activity] {
        updateableActivities.value
    }
    
    private let mintMetadata: StoredMintMetadata
    private let container: Container
    private let sessionContainer: SessionContainer
    private let session: Session
    private let database: Database
    
    // MARK: - Init -
    
    init(mintMetadata: StoredMintMetadata, container: Container, sessionContainer: SessionContainer) {
        self.mintMetadata     = mintMetadata
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        let database          = sessionContainer.database
        self.database         = database
        
        self._updateableActivities = .init(wrappedValue: Updateable {
            (try? database.getActivities(mint: mintMetadata.mint)) ?? []
        })
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Section {
                    ForEach(activities) { activity in
                        row(activity: activity)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(.rowSeparator)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CurrencyLabel(
                        imageURL: mintMetadata.imageURL,
                        name: mintMetadata.name,
                        amount: nil
                    )
                }
            }
        }
        .dialog(item: $dialogItem)
    }
    
    @ViewBuilder private func row(activity: Activity) -> some View {
        Button {
            if BetaFlags.shared.hasEnabled(.transactionDetails) {
                selectedActivity = activity
            } else {
                rowAction(activity: activity)
            }
        } label: {
            VStack {
                HStack {
                    Text(activity.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Spacer()
                    AmountText(
                        flagStyle: activity.exchangedFiat.converted.currencyCode.flagStyle,
                        flagSize: .small,
                        content: activity.exchangedFiat.converted.formatted()
                    )
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                }
                
                HStack {
                    Text(activity.date.formattedRelatively(useTimeForToday: true))
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
//                    if activity.exchangedFiat.converted.currencyCode != .usd {
//                        Text(activity.exchangedFiat.usdc.formatted())
//                            .font(.appTextSmall)
//                            .foregroundStyle(Color.textSecondary)
//                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
    
    // MARK: - Action -
    
    private func rowAction(activity: Activity) {
        if let cashLinkMetadata = activity.cancellableCashLinkMetadata {
            cancelCashLinkAction(
                activity: activity,
                metadata: cashLinkMetadata
            )
        }
    }
    
    private func cancelCashLinkAction(activity: Activity, metadata: Activity.CashLinkMetadata) {
        dialogItem = .init(
            style: .destructive,
            title: "Cancel \(activity.exchangedFiat.converted.formatted()) Transfer?",
            subtitle: "The money will be returned to your wallet.",
            dismissable: true
        ) {
            .destructive("Cancel Transfer") {
                cancelCashLink(metadata: metadata)
            };
            .cancel()
        }
    }
    
    private func cancelCashLink(metadata: Activity.CashLinkMetadata) {
        Task {
            do {
                try await session.cancelCashLink(giftCardVault: metadata.vault)
            } catch {
                dialogItem = .init(
                    style: .destructive,
                    title: "Failed to Cancel Transfer",
                    subtitle: "Something went wrong. Please try again later",
                    dismissable: true
                ) {
                    .okay(kind: .destructive)
                }
            }
        }
    }
}
