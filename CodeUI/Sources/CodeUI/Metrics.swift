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
    
    public static let buttonHeight: CGFloat = 64.0
    public static let buttonHeightThin: CGFloat = 44.0
    public static let buttonRadius: CGFloat = 6.0
    public static let buttonPadding: CGFloat = 20.0
    public static let buttonLineWidth: CGFloat = 1.0
    
    public static let chatMessageRadiusLarge: CGFloat = 10.0
    public static let chatMessageRadiusSmall: CGFloat = 3.0
    
    public static var localizedDecimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }
    
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
