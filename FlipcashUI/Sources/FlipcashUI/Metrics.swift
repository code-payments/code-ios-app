//
//  Metrics.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public enum Metrics {}

// MARK: - Button -

extension Metrics {
    
    /// The height of a full-width capsule button.
    public static let buttonHeight: CGFloat = 54.0
    public static let buttonHeightThin: CGFloat = 44.0
    /// The gap between two buttons that sit together, stacked or side by side.
    public static let buttonGap: CGFloat = 12.0
    /// The corner radius of fields, containers and cards; buttons are capsules and never read it.
    public static let buttonRadius: CGFloat = 6.0
    public static let boxRadius: CGFloat = 12.0
    public static let buttonPadding: CGFloat = 20.0
    public static let buttonLineWidth: CGFloat = 1.0

    /// The scale a button shrinks to while it's held.
    public static let buttonPressScale: CGFloat = 0.95
    /// The opacity a held button dims to in place of the scale under Reduce Motion.
    public static let buttonPressDim: Double = 0.7
    /// The spring a button's press and release ride.
    public static let buttonPressAnimation: Animation = .spring(duration: 0.2, bounce: 0)

    public static func inputFieldStrokeColor(highlighted: Bool) -> Color {
        if highlighted {
            return .textSecondary.opacity(0.7)
        } else {
            return .textSecondary.opacity(0.3)
        }
    }
    
    public static func inputFieldBorderWidth(highlighted: Bool) -> CGFloat {
        if highlighted {
            return 2
        } else {
            return 1
        }
    }
}
