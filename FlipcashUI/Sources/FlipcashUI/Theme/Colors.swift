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
    public static let mainAccent          = Color(r: 255, g: 255, b: 255)
    
    public static let textMain            = Color(r: 255, g: 255, b: 255)
    public static let textSecondary       = Color(r: 118, g: 128, b: 122)
    public static let textAction          = Color(r: 15,  g: 12,  b: 31)
    public static let textActionDisabled  = Color(r: 72,  g: 84,  b: 77)
    public static let textGoogle          = Color(r: 47,  g: 22,  b: 175)
    public static let textError           = Color(r: 255, g: 131, b: 131)
    public static let textSuccess         = Color(r: 73 , g: 213, b: 23)
    public static let textWarning         = Color(r: 255, g: 243, b: 131)
    
    public static let action              = Color(r: 255, g: 255, b: 255)
    public static let actionDisabled      = Color(r: 23,  g: 39,  b: 29)
    
    public static let bannerDark          = Color(r: 15,  g: 12,  b: 31)
    public static let bannerError         = Color(r: 188, g: 52,  b: 52)
    public static let bannerInfo          = Color(r: 26,  g: 49,  b: 37)
    public static let bannerWarning       = Color(r: 241, g: 171, b: 31)
    public static let bannerSuccess       = Color(r: 9,   g: 85,  b: 11)
    
    public static let button              = Color(r: 28,  g: 24,  b: 52)
    
    public static let backgroundMain      = Color(r: 0,   g: 26,  b: 12)
    public static let backgroundAction    = Color(r: 255, g: 255, b: 255)
    public static let backgroundRow       = Color(r: 7,   g: 31,  b: 16)
    public static let rowSeparator        = Color(r: 255, g: 255, b: 255, o: 0.1)
    
    public static let checkmarkBackground = Color(r: 255, g: 255, b: 255)
    
    public static let cameraOverlay       = Color(r: 0, g: 0, b: 0, o: 0.4)
    
    public static let receiptGray         = Color(r: 69, g: 70, b: 78)
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

#if canImport(UIKit)

import UIKit

extension UIColor {
    public static let mainAccent          = UIColor(r: 255, g: 255, b: 255)
    
    public static let textMain            = UIColor(r: 255, g: 255, b: 255)
    public static let textSecondary       = UIColor(r: 118, g: 128, b: 122)
    public static let textAction          = UIColor(r: 15,  g: 12,  b: 31)
    public static let textActionDisabled  = UIColor(r: 72,  g: 84,  b: 77)
    public static let textGoogle          = UIColor(r: 47,  g: 22,  b: 175)
    public static let textError           = UIColor(r: 255, g: 131, b: 131)
    public static let textSuccess         = UIColor(r: 73 , g: 213, b: 23)
    public static let textWarning         = UIColor(r: 255, g: 243, b: 131)
    
    public static let action              = UIColor(r: 255, g: 255, b: 255)
    public static let actionDisabled      = UIColor(r: 23,  g: 39,  b: 29)
    
    public static let bannerDark          = UIColor(r: 15,  g: 12,  b: 31)
    public static let bannerError         = UIColor(r: 188, g: 52,  b: 52)
    public static let bannerInfo          = UIColor(r: 0,   g: 26,  b: 12)
    public static let bannerWarning       = UIColor(r: 241, g: 171, b: 31)
    public static let bannerSuccess       = UIColor(r: 9,   g: 85,  b: 11)
    
    public static let button              = UIColor(r: 28,  g: 24,  b: 52)
    
    public static let backgroundMain      = UIColor(r: 0,   g: 26,  b: 12)
    public static let backgroundAction    = UIColor(r: 255, g: 255, b: 255)
    public static let backgroundRow       = UIColor(r: 17,  g: 20,  b: 42)
    public static let rowSeparator        = UIColor(r: 255, g: 255, b: 255, o: 0.1)
    
    public static let checkmarkBackground = UIColor(r: 115, g: 121, b: 160)
    
    public static let cameraOverlay       = UIColor(r: 0, g: 0, b: 0, o: 0.4)
    
    public static let receiptGray         = UIColor(r: 69, g: 70, b: 78)
}

// MARK: - Color -

extension UIColor {
    
    var view: Color {
        Color(self)
    }
    
    convenience init(r: Double, g: Double, b: Double, o: Double = 1.0) {
        self.init(
            red:   CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue:  CGFloat(b) / 255.0,
            alpha: CGFloat(o)
        )
    }
}

#endif
