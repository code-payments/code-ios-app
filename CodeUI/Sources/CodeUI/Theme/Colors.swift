//
//  Color.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

extension Color {
    public static var mainAccent: Color                { return colorForKey(.mainAccent) }
    public static var textMain: Color                  { return colorForKey(.textMain) }
    public static var textSecondary: Color             { return colorForKey(.textSecondary) }
    public static var textAction: Color                { return colorForKey(.textAction) }
    public static var textGoogle: Color                { return colorForKey(.textGoogle) }
    public static var textError: Color                 { return colorForKey(.textError) }
    public static var textSuccess: Color               { return colorForKey(.textSuccess) }
    public static var textWarning: Color               { return colorForKey(.textWarning) }
    public static var textActionDisabled: Color        { return colorForKey(.textActionDisabled) }
    public static var bannerDark: Color                { return colorForKey(.bannerDark) }
    public static var bannerError: Color               { return colorForKey(.bannerError) }
    public static var bannerInfo: Color                { return colorForKey(.bannerInfo) }
    public static var bannerWarning: Color             { return colorForKey(.bannerWarning) }
    public static var action: Color                    { return colorForKey(.action) }
    public static var actionDisabled: Color            { return colorForKey(.actionDisabled) }
    public static var backgroundMain: Color            { return colorForKey(.backgroundMain) }
    public static var backgroundAction: Color          { return colorForKey(.backgroundAction) }
    public static var backgroundRow: Color             { return colorForKey(.backgroundRow) }
    public static var rowSeparator: Color              { return colorForKey(.rowSeparator) }
    public static var backgroundMessageReceived: Color { return colorForKey(.backgroundMessageReceived) }
    public static var backgroundMessageSent: Color     { return colorForKey(.backgroundMessageSent) }
    public static var checkmarkBackground: Color       { return colorForKey(.checkmarkBackground) }
    public static var cameraOverlay: Color             { return colorForKey(.cameraOverlay) }
    public static var receiptGray: Color               { return colorForKey(.receiptGray) }
    public static var chartLine: Color                 { return colorForKey(.chartLine) }
}

extension UIColor {
    public static var mainAccent: UIColor                { UIColor(.mainAccent) }
    public static var textMain: UIColor                  { UIColor(.textMain) }
    public static var textSecondary: UIColor             { UIColor(.textSecondary) }
    public static var textAction: UIColor                { UIColor(.textAction) }
    public static var textGoogle: UIColor                { UIColor(.textGoogle) }
    public static var textError: UIColor                 { UIColor(.textError) }
    public static var textSuccess: UIColor               { UIColor(.textSuccess) }
    public static var textWarning: UIColor               { UIColor(.textWarning) }
    public static var textActionDisabled: UIColor        { UIColor(.textActionDisabled) }
    public static var bannerDark: UIColor                { UIColor(.bannerDark) }
    public static var bannerError: UIColor               { UIColor(.bannerError) }
    public static var bannerInfo: UIColor                { UIColor(.bannerInfo) }
    public static var bannerWarning: UIColor             { UIColor(.bannerWarning) }
    public static var action: UIColor                    { UIColor(.action) }
    public static var actionDisabled: UIColor            { UIColor(.actionDisabled) }
    public static var backgroundMain: UIColor            { UIColor(.backgroundMain) }
    public static var backgroundAction: UIColor          { UIColor(.backgroundAction) }
    public static var backgroundRow: UIColor             { UIColor(.backgroundRow) }
    public static var rowSeparator: UIColor              { UIColor(.rowSeparator) }
    public static var backgroundMessageReceived: UIColor { UIColor(.backgroundMessageReceived) }
    public static var backgroundMessageSent: UIColor     { UIColor(.backgroundMessageSent) }
    public static var checkmarkBackground: UIColor       { UIColor(.checkmarkBackground) }
    public static var cameraOverlay: UIColor             { UIColor(.cameraOverlay) }
    public static var receiptGray: UIColor               { UIColor(.receiptGray) }
    public static var chartLine: UIColor                 { UIColor(.chartLine) }
}

extension Color {
    
    private enum ColorKey: String {
        case mainAccent
        case textMain
        case textSecondary
        case textAction
        case textGoogle
        case textError
        case textSuccess
        case textWarning
        case textActionDisabled
        case bannerDark
        case bannerError
        case bannerInfo
        case bannerWarning
        case action
        case actionDisabled
        case backgroundMain
        case backgroundAction
        case backgroundRow
        case rowSeparator
        case backgroundMessageReceived
        case backgroundMessageSent
        case checkmarkBackground
        case cameraOverlay
        case receiptGray
        case chartLine
    }
    
    private static var isFlipchat: Bool = {
        let bundleID = try? InfoPlist.bundleIdentifier(bundle: nil)
        if bundleID == "com.kin.code.oct24" {
            return true
        } else {
            return false
        }
    }()
    
    private static func colorForKey(_ key: ColorKey) -> Color {
        if isFlipchat {
            return colorForFlipchat(key: key)
        } else {
            return colorForCode(key: key)
        }
    }
    
    private static func colorForCode(key: ColorKey) -> Color {
        switch key {
        case .mainAccent:                return Color(r: 255, g: 255, b: 255)
        case .textMain:                  return Color(r: 255, g: 255, b: 255)
        case .textSecondary:             return Color(r: 115, g: 121, b: 160)
        case .textAction:                return Color(r: 15,  g: 12,  b: 31)
        case .textGoogle:                return Color(r: 47,  g: 22,  b: 175)
        case .textError:                 return Color(r: 255, g: 131, b: 131)
        case .textSuccess:               return Color(r: 73,  g: 213, b: 23)
        case .textWarning:               return Color(r: 255, g: 243, b: 131)
        case .textActionDisabled:        return Color(r: 48,  g: 45,  b: 63)
        case .bannerDark:                return Color(r: 15,  g: 12,  b: 31)
        case .bannerError:               return Color(r: 188, g: 52,  b: 52)
        case .bannerInfo:                return Color(r: 86,  g: 92,  b: 134)
        case .bannerWarning:             return Color(r: 241, g: 171, b: 31)
        case .action:                    return Color(r: 255, g: 255, b: 255)
        case .actionDisabled:            return Color(r: 27,  g: 25,  b: 41)
        case .backgroundMain:            return Color(r: 15,  g: 12,  b: 31)
        case .backgroundAction:          return Color(r: 255, g: 255, b: 255)
        case .backgroundRow:             return Color(r: 17,  g: 20,  b: 42)
        case .rowSeparator:              return Color(r: 255, g: 255, b: 255, o: 0.08)
        case .backgroundMessageReceived: return Color(r: 31,  g: 26,  b: 52)
        case .backgroundMessageSent:     return Color(r: 68,  g: 48,  b: 145)
        case .checkmarkBackground:       return Color(r: 115, g: 121, b: 160)
        case .cameraOverlay:             return Color(r: 0,   g: 0,   b: 0,   o: 0.4)
        case .receiptGray:               return Color(r: 69,  g: 70,  b: 78)
        case .chartLine:                 return Color(r: 86,  g: 92,  b: 134)
        }
    }

    private static func colorForFlipchat(key: ColorKey) -> Color {
        switch key {
        case .mainAccent:                return Color(r: 255, g: 255, b: 255) // Done
        case .textMain:                  return Color(r: 255, g: 255, b: 255) // Done
        case .textSecondary:             return Color(r: 159, g: 151, b: 196) // Done
        case .textAction:                return Color(r: 54,  g: 39,  b: 116) // Done
        case .textGoogle:                return Color(r: 47,  g: 22,  b: 175)
        case .textError:                 return Color(r: 255, g: 131, b: 131)
        case .textSuccess:               return Color(r: 73,  g: 213, b: 23)
        case .textWarning:               return Color(r: 255, g: 243, b: 131)
        case .textActionDisabled:        return Color(r: 255, g: 255, b: 255, o: 0.2) // Done
        case .bannerDark:                return Color(r: 15,  g: 12,  b: 31)
        case .bannerError:               return Color(r: 188, g: 52,  b: 52)
        case .bannerInfo:                return Color(r: 86,  g: 92,  b: 134)
        case .bannerWarning:             return Color(r: 241, g: 171, b: 31)
        case .action:                    return Color(r: 255, g: 255, b: 255) // Done
        case .actionDisabled:            return Color(r: 43,  g: 31,  b: 90)  // Done
        case .backgroundMain:            return Color(r: 54,  g: 39,  b: 116) // Done
        case .backgroundAction:          return Color(r: 255, g: 255, b: 255) // Done
        case .backgroundRow:             return Color(r: 44,  g: 33,  b: 88)  // Done
        case .rowSeparator:              return Color(r: 255, g: 255, b: 255, o: 0.08)
        case .backgroundMessageReceived: return Color(r: 44,  g: 33,  b: 88)  // Done
        case .backgroundMessageSent:     return Color(r: 68,  g: 48,  b: 145) // Done
        case .checkmarkBackground:       return Color(r: 115, g: 121, b: 160)
        case .cameraOverlay:             return Color(r: 0,   g: 0,   b: 0,   o: 0.4)
        case .receiptGray:               return Color(r: 69,  g: 70,  b: 78)
        case .chartLine:                 return Color(r: 86,  g: 92,  b: 134)
        }
    }
}

// MARK: - RGB -

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

// MARK: - Gradients -

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
