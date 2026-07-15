//
//  Pill.swift
//  FlipcashUI
//

import SwiftUI

public extension View {
    /// Styles the receiver as a fully-rounded pill with muted text — e.g. the
    /// "Unknown Contact" tag on a recipient row.
    func pill() -> some View {
        self
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(Color.backgroundRow)
            }
    }
}
