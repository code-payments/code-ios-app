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

        registerFont(named: "RobotoMono-Regular", extension: "ttf")
    }

    /// Registers only the faces a notification extension renders (Avenir Medium + Demi). The full
    /// set adds unused fonts the extension's tight memory budget can't spare.
    public static func registerNotificationFonts() {
        registerFont(named: "AvenirNextLTPro-Medium", extension: "otf")
        registerFont(named: "AvenirNextLTPro-Demi", extension: "otf")
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

    public static func roboto(size: CGFloat) -> UIFont {
        UIFont(name: "RobotoMono-Regular", size: size)!
    }
    
    public static func `default`(size: CGFloat, weight: Weight = .regular) -> UIFont {
        UIFont(name: avenir(weight: weight), size: size)!
    }

    /// The app face at `weight`, slanted to stand in for an italic, which the bundled Avenir lacks.
    public static func defaultOblique(size: CGFloat, weight: Weight = .regular) -> UIFont {
        oblique(named: avenir(weight: weight), size: size)
    }

    fileprivate static func oblique(named name: String, size: CGFloat) -> UIFont {
        // Skia's fake-italic skew, so the slant matches what Compose synthesizes on Android.
        let skew = CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0)
        let descriptor = UIFont(name: name, size: size)!.fontDescriptor.withMatrix(skew)
        return UIFont(descriptor: descriptor, size: size)
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
}

#endif

// MARK: - SwiftUI -

extension Font {

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
        case .medium, .semibold:
            return "AvenirNextLTPro-Medium"
        case .bold, .heavy, .black:
            return "AvenirNextLTPro-Demi"
        default:
            fatalError("[FontBook] Failed to initialize SwiftUI app font. Unsupported font weight requested: \(weight)")
        }
    }
}

#if canImport(UIKit)

extension Font {

    /// ``UIFont/defaultOblique(size:weight:)`` for SwiftUI, scaled for `dynamicTypeSize` the way
    /// ``Font/default(size:weight:)`` scales with the body text style.
    public static func defaultOblique(size: CGFloat, weight: Weight = .regular, dynamicTypeSize: DynamicTypeSize) -> Font {
        // A `Font` built from a `UIFont` doesn't track Dynamic Type, so the size is scaled here.
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaledSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: size, compatibleWith: traits)
        return Font(UIFont.oblique(named: avenir(weight: weight), size: scaledSize))
    }
}

#endif
