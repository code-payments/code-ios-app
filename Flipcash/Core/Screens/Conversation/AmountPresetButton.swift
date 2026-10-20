//
//  AmountPresetButton.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// One chip in a row of preset amounts, or the custom-entry ellipsis beside them (node
/// 10127:118261). The selected one inverts to a white fill.
struct AmountPresetButton<Label: View>: View {

    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    /// Node 10127:118260 — the preset row is 61pt tall.
    private static var height: CGFloat { 61 }

    var body: some View {
        Button(action: action) {
            label()
                .font(.appTextXL)
                .tracking(-0.88)
                // Four chips share the row, so a custom amount wider than a preset shrinks to fit
                // rather than wrapping or clipping.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isSelected ? Color.textAction : Color.textMain)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .background(
                    isSelected ? Color.action : Color.white.opacity(0.1),
                    in: .rect(cornerRadius: Metrics.buttonRadius)
                )
                .contentShape(.rect(cornerRadius: Metrics.buttonRadius))
        }
        .buttonStyle(.plain)
    }
}
