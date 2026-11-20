//
//  AmountPresetButton.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// One chip in a row of preset amounts, or the custom-entry ellipsis beside them (node
/// 10127:118261). The selected one inverts to the action fill.
struct AmountPresetButton<Label: View>: View {

    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.appTextXL)
                .tracking(-0.88)
                // Four chips share the row, so a custom amount wider than a preset shrinks to fit
                // rather than wrapping or clipping.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Keeps a shrunk custom amount clear of the capsule's round ends.
                .padding(.horizontal, 8)
                .foregroundStyle(isSelected ? Color.textAction : Color.textMain)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.buttonHeight)
                .background(
                    isSelected ? Color.action : Color.fillControl,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
