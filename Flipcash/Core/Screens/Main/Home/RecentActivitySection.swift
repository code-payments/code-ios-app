//
//  RecentActivitySection.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// The "Recent" activity preview: a tappable header that opens the full history,
/// over a short list of ``WalletActivityRow``s. Shared by the wallet (all tokens)
/// and the currency info screen (a single token), which differ only in what the
/// header opens.
struct RecentActivitySection: View {

    let activities: [Activity]
    /// Opens the full history — cross-token on the wallet, per-token on currency info.
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header is the "dive in" affordance — the rows themselves are a
            // non-interactive preview.
            Button(action: onShowAll) {
                HStack(spacing: 8) {
                    Text("Recent")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            ForEach(activities) { activity in
                WalletActivityRow(activity: activity)
            }
        }
    }
}
