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

    /// Registers only the faces the app extensions render (Avenir Medium + Demi). The full set adds
    /// unused fonts an extension's tight memory budget can't spare.
    public static func registerExtensionFonts() {
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
        .systemFont(ofSize: size, weight: appWeight(weight))
    }

    /// The app face at `weight`, slanted to stand in for an italic.
    public static func defaultOblique(size: CGFloat, weight: Weight = .regular) -> UIFont {
        oblique(.default(size: size, weight: weight), size: size)
    }

    fileprivate static func oblique(_ font: UIFont, size: CGFloat) -> UIFont {
        // Skia's fake-italic skew, so the slant matches what Compose synthesizes on Android.
        let skew = CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0)
        let descriptor = font.fontDescriptor.withMatrix(skew)
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The app's three steps on SF: the bold weights land on Semibold, where Avenir's Demi sat.
    private static func appWeight(_ weight: Weight) -> Weight {
        switch weight {
        case .ultraLight, .thin, .light, .regular: .regular
        case .medium: .medium
        default: .semibold
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
        // `.custom(_:size:)` scaled with the body style; this keeps SF on Dynamic Type the same way.
        #if canImport(UIKit)
        .system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: size), weight: appWeight(weight))
        #else
        .system(size: size, weight: appWeight(weight))
        #endif
    }

    /// The app's three steps on SF: the bold weights land on Semibold, where Avenir's Demi sat.
    private static func appWeight(_ weight: Weight) -> Weight {
        switch weight {
        case .ultraLight, .thin, .light, .regular: .regular
        case .medium: .medium
        default: .semibold
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
        let uiWeight: UIFont.Weight = switch weight {
        case .medium: .medium
        case .semibold, .bold, .heavy, .black: .semibold
        default: .regular
        }
        return Font(UIFont.defaultOblique(size: scaledSize, weight: uiWeight))
    }
}

#endif
