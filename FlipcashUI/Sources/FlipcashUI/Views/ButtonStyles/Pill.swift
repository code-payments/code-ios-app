//
//  Pill.swift
//  FlipcashUI
//

import SwiftUI

/// Visual style for a compact pill label (small text on a rounded fill).
public enum PillStyle {
    /// Subtle row-fill background — e.g. the "Invite" affordance.
    case standard
    /// Solid white fill — e.g. the "Settings" affordance.
    case prominent

    var textColor: Color {
        switch self {
        case .standard:  .textMain
        case .prominent: .backgroundMain
        }
    }

    var fillColor: Color {
        switch self {
        case .standard:  .backgroundRow
        case .prominent: .textMain
        }
    }
}

public extension View {
    /// Styles the receiver as a compact pill. Used for the non-interactive pill
    /// affordance inside a tappable row (the whole row is the tap target), e.g.
    /// "Invite" and "Settings".
    func pill(_ style: PillStyle) -> some View {
        self
            .font(.appTextSmall)
            .foregroundStyle(style.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                    .fill(style.fillColor)
            }
    }
}
