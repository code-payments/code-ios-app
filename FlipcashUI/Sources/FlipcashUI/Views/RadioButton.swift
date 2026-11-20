//
//  RadioButton.swift
//  FlipcashUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

/// The app's selection indicator for a row: a ring in the main text colour, filled with a checkmark
/// when selected.
///
/// It only reports state. The row around it is the tap target and carries the `.isSelected`
/// accessibility trait, so the indicator is hidden from VoiceOver.
public struct RadioButton: View {

    public let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color.checkmarkBackground)
                Image.asset(.checkmark)
                    .renderingMode(.template)
                    .foregroundStyle(Color.radioCheck)
            } else {
                Circle()
                    .strokeBorder(Color.textMain)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private extension Color {
    /// The check on the selected disc: the asset's own near-black in dark, white on the ink disc in light.
    static let radioCheck = Color(light: .white, dark: Color(r: 0, g: 26, b: 12))
}

// MARK: - Previews -

#Preview {
    Background(color: .backgroundMain) {
        VStack {
            RadioButton(isSelected: true)
            RadioButton(isSelected: false)
        }
    }
}
