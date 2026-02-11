//
//  Color.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

extension Color {
    public static let textMain            = Color.white
    public static let textSecondary       = Color(r: 123, g: 123, b: 123)
    public static let textAction          = Color.black
    public static let textActionDisabled  = Color(r: 78,  g: 78,  b: 78)
    public static let textError           = Color(r: 255, g: 131, b: 131)
    public static let textSuccess         = Color(r: 73 , g: 213, b: 23)
    public static let textWarning         = Color(r: 255, g: 243, b: 131)
    
    public static let action              = Color.white
    public static let actionDisabled      = Color(r: 30,  g: 30,  b: 30)
    public static let textActionSecondaryDisabled = Color(r: 24, g: 24, b: 24)
    public static let strokeDisabled      = Color(r: 48,  g: 48,  b: 48)
    
    public static let bannerDark          = Color(r: 15,  g: 12,  b: 31)
    public static let bannerError         = Color(r: 188, g: 52,  b: 52)
    public static let bannerInfo          = Color(r: 26,  g: 49,  b: 37)
    public static let bannerWarning       = Color(r: 241, g: 171, b: 31)
    public static let bannerSuccess       = Color("backgroundSecondary")
        
    public static let backgroundMain      = Color("background")
    public static let backgroundSecondary = Color("backgroundSecondary")
    public static let backgroundAction    = Color.white
    public static let backgroundRow       = Color.white.opacity(0.05)
    public static let rowSeparator        = Color.white.opacity(0.1)
    
    public static let checkmarkBackground = Color.white
    
    public static let cameraOverlay       = Color.black.opacity(0.4)
    
    public static let receiptGray         = Color(r: 69, g: 70, b: 78)
        
    public struct Sentiment {
        public static let positive          = Color(r: 49,  g: 156, b: 88)
        public static let positiveSecondary = Color(r: 17,  g: 53,  b: 34)
        public static let negative          = Color(r: 228, g: 42,  b: 42)
        public static let negativeSecondary = Color(r: 60,  g: 37,  b: 37)
    }
    
}

// MARK: - Color -

extension Color {
    public init(r: Double, g: Double, b: Double, o: Double = 1.0) {
        self.init(
            red:     r / 255.0,
            green:   g / 255.0,
            blue:    b / 255.0,
            opacity: o
        )
    }

    /// Initialize a Color from a hex string in `#RRGGBB` format.
    /// Returns `nil` if the string is not a valid hex color.
    public init?(hex: String) {
        var hexString = hex
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6, let rgb = UInt64(hexString, radix: 16) else {
            return nil
        }

        self.init(
            r: Double((rgb >> 16) & 0xFF),
            g: Double((rgb >>  8) & 0xFF),
            b: Double( rgb        & 0xFF)
        )
    }
}

extension LinearGradient {
    public static let background = LinearGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: Color(r: 22, g: 18, b: 39), location: 0.0),
            Gradient.Stop(color: Color(r: 24, g: 21, b: 42), location: 0.495),
            Gradient.Stop(color: Color(r: 15, g: 12, b: 31), location: 0.505),
            Gradient.Stop(color: Color(r: 17, g: 13, b: 33), location: 1.0),
        ]),
        startPoint: UnitPoint(x: 1.0, y: 0.05),
        endPoint:   UnitPoint(x: 0.0, y: 0.54)
    )
}

extension LinearGradient {
    public static let loginBillBackground = LinearGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: Color(r: 31, g: 35, b: 35), location: 0.0),
            Gradient.Stop(color: Color(r: 18, g: 21, b: 20), location: 1.0),
        ]),
        startPoint: UnitPoint(x: 0.5, y: 0.0),
        endPoint:   UnitPoint(x: 0.5, y: 1.0)
    )
}
