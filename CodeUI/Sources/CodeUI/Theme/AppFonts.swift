//
//  AppFonts.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

extension Font {
    public static let appDisplayLarge:  Font = .default(size: 55, weight: .bold)
    public static let appDisplayMedium: Font = .default(size: 40, weight: .bold)
    public static let appDisplaySmall:  Font = .default(size: 24, weight: .bold)
    public static let appDisplayXS:     Font = .default(size: 20, weight: .bold)
    
    public static let appKeyboard:      Font = .default(size: 30, weight: .regular)
    
    public static let appTitle:         Font = .default(size: 20, weight: .bold)
    public static let appBarButton:     Font = .default(size: 18, weight: .bold)
    
    public static let appTextXL:        Font = .default(size: 22, weight: .bold)
    public static let appTextLarge:     Font = .default(size: 20, weight: .bold)
    public static let appTextMedium:    Font = .default(size: 16, weight: .bold)
    public static let appTextSmall:     Font = .default(size: 14, weight: .bold)
    public static let appTextMessage:   Font = .default(size: 16, weight: .medium)
    public static let appTextBody:      Font = .default(size: 16, weight: .regular)
    public static let appTextHeading:   Font = .default(size: 12, weight: .bold)
    public static let appTextCaption:   Font = .default(size: 12, weight: .bold)
    
    public static let appTextAccessKey: Font = .default(size: 9, weight: .bold)
    public static let appTextSeed:      Font = .fixedWidth(size: 16)
    
    public static let appReceiptMedium: Font = .roboto(size: 16)
}

#if canImport(UIKit)

import UIKit

extension UIFont {
    public static let appDisplayLarge:  UIFont = .default(size: 55, weight: .bold)
    public static let appDisplayMedium: UIFont = .default(size: 40, weight: .bold)
    public static let appDisplaySmall:  UIFont = .default(size: 24, weight: .bold)
    public static let appDisplayXS:     UIFont = .default(size: 20, weight: .bold)
    
    public static let appKeyboard:      UIFont = .default(size: 30, weight: .regular)
    
    public static let appTitle:         UIFont = .default(size: 20, weight: .bold)
    public static let appBarButton:     UIFont = .default(size: 18, weight: .bold)
    
    public static let appTextXL:        UIFont = .default(size: 22, weight: .bold)
    public static let appTextLarge:     UIFont = .default(size: 20, weight: .bold)
    public static let appTextMedium:    UIFont = .default(size: 16, weight: .bold)
    public static let appTextSmall:     UIFont = .default(size: 14, weight: .bold)
    public static let appTextMessage:   UIFont = .default(size: 16, weight: .medium)
    public static let appTextBody:      UIFont = .default(size: 16, weight: .regular)
    public static let appTextHeading:   UIFont = .default(size: 12, weight: .bold)
    public static let appTextCaption:   UIFont = .default(size: 12, weight: .bold)
    
    public static let appTextAccessKey: UIFont = .default(size: 9, weight: .bold)
    public static let appTextSeed:      UIFont = .fixedWidth(size: 16)
    
    public static let appReceiptMedium: UIFont = .roboto(size: 16)
}

#endif
