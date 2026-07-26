//
//  BetaFlagToggleRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A single beta-flag toggle row, shared by the developer "Beta Flags" screen
/// and the public "Beta Features" screen.
struct BetaFlagToggleRow: View {

    let option: BetaFlags.Option
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.localizedTitle)
                        .foregroundStyle(.textMain)
                        .font(.appTextMedium)
                    Text(option.localizedDescription)
                        .foregroundStyle(.textSecondary)
                        .font(.appTextHeading)
                        .multilineTextAlignment(.leading)
                }
                .padding(.trailing, 20)
            }
            .tint(.textSuccess)
        }
        .padding(20)
        .vSeparator(color: .rowSeparator, position: .bottom)
    }
}
