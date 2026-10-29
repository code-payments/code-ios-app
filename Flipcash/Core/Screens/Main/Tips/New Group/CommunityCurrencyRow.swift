//
//  CommunityCurrencyRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The form's tappable currency row: the chosen token's icon and name, and a chevron.
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
