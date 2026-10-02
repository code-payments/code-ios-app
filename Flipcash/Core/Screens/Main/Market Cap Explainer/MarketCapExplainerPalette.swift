//
//  MarketCapExplainerPalette.swift
//  Flipcash
//

import SwiftUI

/// Colors shared across the market cap explainer.
enum MarketCapExplainerPalette {
    /// `#009F50`, the green of the curve, slider fill, icon and positive appreciation.
    static let green = Color(red: 0, green: 159 / 255, blue: 80 / 255)

    /// `#FF8383`, negative appreciation. Matches Android's `errorText`.
    static let red = Color(red: 1, green: 131 / 255, blue: 131 / 255)
}
