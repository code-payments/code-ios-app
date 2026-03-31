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

    @Environment(Session.self) private var session

    @State private var activities: Updateable<[Activity]>

    @State private var dialogItem: DialogItem?

    private let mintMetadata: StoredMintMetadata

    // MARK: - Init -

    init(mintMetadata: StoredMintMetadata, database: Database) {
        self.mintMetadata = mintMetadata
        self.activities = Updateable {
            (try? database.getActivities(mint: mintMetadata.mint)) ?? []
        }
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Section {
                    ForEach(activities.value) { activity in
                        ActivityRow(activity: activity) {
                            rowAction(activity: activity)
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(.rowSeparator)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Transaction History")
        }
        .dialog(item: $dialogItem)
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
                ErrorReporting.captureError(error, reason: "Failed to cancel cash link", metadata: [
                    "vault": metadata.vault.base58,
                ])
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

// MARK: - Activity Row -

private struct ActivityRow: View {
    let activity: Activity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
                }
            }
        }
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
}
