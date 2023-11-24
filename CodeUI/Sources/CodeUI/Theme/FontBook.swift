//
//  FontBook.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public enum FontBook {
    
    private static let bundle = Bundle.module
    
    public static func registerApplicationFonts() {
        registerFont(named: "AvenirNextLTPro-Demi", extension: "otf")
        registerFont(named: "AvenirNextLTPro-Medium", extension: "otf")
        registerFont(named: "AvenirNextLTPro-Regular", extension: "otf")
        
        registerFont(named: "Manrope-ExtraLight", extension: "ttf")
        registerFont(named: "Manrope-Light", extension: "ttf")
        registerFont(named: "Manrope-Regular", extension: "ttf")
        registerFont(named: "Manrope-Medium", extension: "ttf")
        registerFont(named: "Manrope-SemiBold", extension: "ttf")
        registerFont(named: "Manrope-Bold", extension: "ttf")
        registerFont(named: "Manrope-ExtraBold", extension: "ttf")
        
        registerFont(named: "RobotoMono-Regular", extension: "ttf")
    }
    
    @discardableResult
    private static func registerFont(named name: String, extension ext: String) -> Bool {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            print("[FontBook] Failed to register font. Font not found: \(name).\(ext)")
            return false
        }
        
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            print("[FontBook] Failed to register font. Failed to create data provider for font: \(name).\(ext)")
            return false
        }
        
        guard let font = CGFont(dataProvider) else {
            print("[FontBook] Failed to register font. Failed to create font: \(name).\(ext)")
            return false
        }
        
        if CTFontManagerRegisterGraphicsFont(font, nil) {
            return true
        } else {
            print("[FontBook] Failed to register font: \(name).\(ext)")
            return false
        }
    }
}

#if canImport(UIKit)

import UIKit

// MARK: - UIKit -

extension UIFont {
    
    public static func fixedWidth(size: CGFloat, weight: Weight = .regular) -> UIFont {
        UIFont(name: "Menlo-Bold", size: size)!
    }
    
    public static func roboto(size: CGFloat) -> UIFont {
        UIFont(name: "RobotoMono-Regular", size: size)!
    }
    
    public static func `default`(size: CGFloat, weight: Weight = .regular) -> UIFont {
        UIFont(name: avenir(weight: weight), size: size)!
    }
    
    private static func avenir(weight: Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return "AvenirNextLTPro-Regular"
        case .medium:
            return "AvenirNextLTPro-Medium"
        case .semibold, .bold, .heavy, .black:
            return "AvenirNextLTPro-Demi"
        default:
            fatalError("[FontBook] Failed to initialize UIKit app font. Unsupported font weight requested: \(weight)")
        }
    }
    
    private static func manrope(weight: Weight) -> String {
        switch weight {
        case .ultraLight:
            return "Manrope-ExtraLight"
        case .thin:
            return "Manrope-ExtraLight"
        case .light:
            return "Manrope-Light"
        case .regular:
            return "Manrope-Regular"
        case .medium:
            return "Manrope-Medium"
        case .semibold:
            return "Manrope-SemiBold"
        case .bold:
            return "Manrope-Bold"
        case .heavy:
            return "Manrope-ExtraBold"
        case .black:
            return "Manrope-ExtraBold"
        default:
            fatalError("[FontBook] Failed to initialize UIKit app font. Unsupported font weight requested: \(weight)")
        }
    }
}

#endif

// MARK: - SwiftUI -

extension Font {
    
    public static func fixedWidth(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("Menlo-Bold", size: size)
    }
    
    public static func roboto(size: CGFloat) -> Font {
        .custom("RobotoMono-Regular", size: size)
    }

    public static func `default`(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(avenir(weight: weight), size: size)
    }
    
    private static func avenir(weight: Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular:
            return "AvenirNextLTPro-Regular"
        case .medium, .semibold, .bold, .heavy, .black:
            return "AvenirNextLTPro-Demi"
        default:
            fatalError("[FontBook] Failed to initialize SwiftUI app font. Unsupported font weight requested: \(weight)")
        }
    }
    
    private static func manrope(weight: Weight) -> String {
        switch weight {
        case .ultraLight:
            return "Manrope-ExtraLight"
        case .thin:
            return "Manrope-ExtraLight"
        case .light:
            return "Manrope-Light"
        case .regular:
            return "Manrope-Regular"
        case .medium:
            return "Manrope-Medium"
        case .semibold:
            return "Manrope-SemiBold"
        case .bold:
            return "Manrope-Bold"
        case .heavy:
            return "Manrope-ExtraBold"
        case .black:
            return "Manrope-ExtraBold"
        default:
            fatalError("[FontBook] Failed to initialize SwiftUI app font. Unsupported font weight requested: \(weight)")
        }
    }
}
